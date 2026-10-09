require "open3"
require "base64"

# A shallow checkout of the OCL repo : reads fr.yml, finds where keys are used, publishes a branch
class OclRepo
  I18N_SRC = "src/ladb_opencutlist/yaml/i18n-src".freeze
  CODE_PATHS = ["src/ladb_opencutlist/js", "src/ladb_opencutlist/twig", "src/ladb_opencutlist/ruby",
                ":(exclude)src/ladb_opencutlist/js/i18n", ":(exclude)src/ladb_opencutlist/js/templates",
                ":(exclude)src/ladb_opencutlist/js/lib", ":(exclude)src/ladb_opencutlist/js/bundles",
                ":(exclude)src/ladb_opencutlist/ruby/lib"].freeze

  Error = Class.new(StandardError)
  BRANCH_FORMAT = %r{\A(?!-)(?!.*\.\.)[A-Za-z0-9._/-]+\z}

  # The branch synced with and published to : chosen on the sync page, OCL_BASE_BRANCH until then
  def self.base_branch(config = Rails.configuration.x.ocl)
    Setting["base_branch"].presence || config.base_branch
  end

  def self.valid_branch?(name)
    name.to_s.match?(BRANCH_FORMAT)
  end

  def initialize(config = Rails.configuration.x.ocl, auth: GithubAuth.new(config))
    @config = config
    @auth = auth
    @dir = config.checkout_dir
  end

  # A remote repo is only pushed to with the tool's own credentials, never the machine's
  def can_push?
    local? || @auth.configured?
  end

  # Brings the checkout to the tip of the base branch (or of another one, to analyze it), returns its sha
  def fetch!(base = base_branch)
    raise Error, I18n.t("ocl_repo.invalid_branch", branch: base) unless self.class.valid_branch?(base)

    if File.directory?(File.join(@dir, ".git"))
      git(*auth, "fetch", "-q", "--depth", "1", "origin", "+#{base}:refs/remotes/origin/#{base}")
    else
      FileUtils.mkdir_p(File.dirname(@dir))
      run("git", *auth, "clone", "--depth", "1", "--branch", base, "--single-branch", @config.repo_url, @dir)
    end
    git("checkout", "-q", "-B", base, "origin/#{base}")
    git("reset", "-q", "--hard", "origin/#{base}")
    git("rev-parse", "HEAD").strip
  end

  def fr_text
    path = File.join(I18N_SRC, "#{Language::SOURCE_CODE}.yml")
    raise Error, I18n.t("ocl_repo.missing_fr", path: path) unless File.file?(File.join(@dir, path))

    File.read(File.join(@dir, path))
  end

  # Quoted literal uses of each key in the code : { key => [[path, line_number, line]] }
  def references(keys)
    keys.index_with do |key|
      out = git_grep("-n", "-F", "-e", "'#{key}'", "-e", "\"#{key}\"")
      out.lines.map { |l| path, line, text = l.split(":", 3); [path, line.to_i, text.to_s.strip] }
    end
  end

  Published = Struct.new(:sha, :files, :leftovers, keyword_init: true)

  # Recreates the i18n branch from the base branch with the given files and key renames, and pushes it.
  # leftovers : uses of a renamed key's old branch still in the code after the rewrite,
  # typically dynamic ones ('tab.cutlist.tooltip.' + name). Returns nil when nothing differs.
  def publish!(files:, renames:, message:)
    raise Error, I18n.t("ocl_repo.no_access") unless can_push?

    branch = @config.i18n_branch
    git("checkout", "-q", "-B", branch, "origin/#{base_branch}")
    files.each { |path, content| File.write(File.join(@dir, path), content) }
    rewrite_code(renames)
    git("add", "-A")
    changed = git("diff", "--cached", "--name-only").lines.map(&:strip)
    return nil if changed.empty?

    leftovers = old_branches(renames).flat_map do |prefix|
      git_grep("-n", "-F", "-e", "'#{prefix}.", "-e", "\"#{prefix}.").lines.map { |l| [prefix, l.strip] }
    end
    name, email = @auth.committer
    git("-c", "user.name=#{name}", "-c", "user.email=#{email}", "commit", "-q", "-m", message)
    git(*auth, "push", "-q", "--force", "origin", "#{branch}:refs/heads/#{branch}")
    Published.new(sha: git("rev-parse", "HEAD").strip, files: changed, leftovers: leftovers)
  ensure
    git("checkout", "-q", base_branch) rescue nil
  end

  def base_branch
    self.class.base_branch(@config)
  end

  private

  # Branches a rename moved keys out of, when no key of the tool stays in them
  def old_branches(renames)
    renames.filter_map { |old, new| [old.rpartition(".").first, new.rpartition(".").first] }
           .reject { |old, new| old == new || old.empty? }.map(&:first).uniq
           .reject { |prefix| Unit.active.where("key LIKE ? ESCAPE '\\'", "#{Unit.sanitize_sql_like(prefix)}.%").exists? }
  end

  def rewrite_code(renames)
    return if renames.empty?

    renames.each do |old_key, new_key|
      files = git_grep("-l", "-F", "-e", "'#{old_key}'", "-e", "\"#{old_key}\"").lines.map(&:strip)
      files.each do |path|
        full = File.join(@dir, path)
        text = File.read(full)
        text = text.gsub("'#{old_key}'", "'#{new_key}'").gsub("\"#{old_key}\"", "\"#{new_key}\"")
        File.write(full, text)
      end
    end
  end

  def git_grep(*args)
    out, status = Open3.capture2("git", "-C", @dir, "grep", *args, "--", *CODE_PATHS)
    raise Error, "git grep failed" unless status.success? || status.exitstatus == 1 # 1 = no match

    out
  end

  def git(*args)
    run("git", "-C", @dir, *args)
  end

  # No prompt, no askpass : a missing or refused credential fails instead of borrowing the machine's
  GIT_ENV = { "GIT_TERMINAL_PROMPT" => "0", "GIT_ASKPASS" => "", "SSH_ASKPASS" => "" }.freeze

  def run(*cmd)
    out, err, status = Open3.capture3(GIT_ENV, *cmd)
    raise Error, "#{cmd.reject { |c| c.include?('Authorization') }.join(' ')} : #{err.strip}" unless status.success?

    out
  end

  def local?
    !@config.repo_url.match?(%r{\A[a-z][a-z0-9+.-]*://|\A[^/]+@}i) || @config.repo_url.start_with?("file://")
  end

  # Credential helpers (osxkeychain, gh...) are disabled ; the token never lands in .git/config
  def auth
    no_helpers = ["-c", "credential.helper=", "-c", "core.askPass="]
    token = @auth.token if !local? && @auth.configured?
    return no_helpers if token.blank?

    [*no_helpers, "-c", "http.extraHeader=Authorization: Basic #{Base64.strict_encode64("x-access-token:#{token}")}"]
  end
end
