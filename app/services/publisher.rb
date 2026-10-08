# Publishes the translations to the OCL repo as a pull request :
# the 18 i18n-src files, plus the code references of keys renamed in the tool
class Publisher
  Result = Struct.new(:status, :plan, :sha, :pr_url, :renames, :warnings, :files, keyword_init: true)
  # status : :needs_sync (the repo's fr.yml has unsynced changes), :unchanged, :published

  def initialize(user, auth: GithubAuth.new(user: user), repo: OclRepo.new(auth: auth), pulls: GithubPulls.new(auth: auth))
    @user = user
    @repo = repo
    @pulls = pulls
  end

  def call
    @repo.fetch!
    plan = SourceSync.new(@repo.fr_text, author: @user).plan
    return Result.new(status: :needs_sync, plan: plan) unless plan.empty?

    renames, deleted = pending_key_changes
    deleted_warnings = deleted_reference_warnings(deleted)
    files = YamlExport.new.files.transform_keys { |name| File.join(OclRepo::I18N_SRC, name) }
    published = @repo.publish!(files: files, renames: renames, message: commit_message(renames, deleted))
    return Result.new(status: :unchanged) unless published

    warnings = published.leftovers.map { |prefix, ref| "Usage restant de l'ancienne branche `#{prefix}` (dynamique ?) : `#{ref}`" } + deleted_warnings
    pr_url = @pulls.open_or_update(title: "Updated translations", body: pr_body(renames, deleted, warnings, published.files)) if @pulls.enabled?
    Publication.create!(branch: Rails.configuration.x.ocl.i18n_branch, commit_sha: published.sha, pr_url: pr_url,
                        fr_hash: Baseline.hash_text(files.fetch(File.join(OclRepo::I18N_SRC, "fr.yml"))), user: @user)
    Result.new(status: :published, sha: published.sha, pr_url: pr_url, renames: renames, warnings: warnings, files: published.files)
  end

  private

  # Keys renamed or deleted in the tool since the repo was last reconciled
  def pending_key_changes
    baseline = Baseline.current
    units = Unit.where(id: baseline.entries.map { |e| e["unit_id"] }.compact).index_by(&:id)
    renames = []
    deleted = []
    baseline.entries.each do |e|
      unit = units[e["unit_id"]] or next
      if unit.archived? then deleted << e["key"]
      elsif unit.key != e["key"] then renames << [e["key"], unit.key]
      end
    end
    [renames, deleted]
  end

  def deleted_reference_warnings(deleted)
    @repo.references(deleted).flat_map do |key, refs|
      refs.map { |path, line, _| "Clé supprimée `#{key}` encore utilisée : #{path}:#{line}" }
    end
  end

  def commit_message(renames, deleted)
    lines = ["~ Updated translations"]
    lines << "" << "Renamed keys :" << renames.map { |o, n| "- #{o} -> #{n}" } if renames.any?
    lines << "" << "Deleted keys :" << deleted.map { |k| "- #{k}" } if deleted.any?
    lines.flatten.join("\n")
  end

  def pr_body(renames, deleted, warnings, changed)
    out = ["Généré par OCL i18n.", "", "**Fichiers modifiés** (#{changed.size}) :", *changed.map { |f| "- `#{f}`" }]
    out += ["", "**Clés renommées** (#{renames.size}), références dans le code réécrites :", *renames.map { |o, n| "- `#{o}` → `#{n}`" }] if renames.any?
    out += ["", "**Clés supprimées** (#{deleted.size}) :", *deleted.map { |k| "- `#{k}`" }] if deleted.any?
    out += ["", "### ⚠ À vérifier à la main", *warnings.map { |w| "- #{w}" }] if warnings.any?
    out.join("\n")
  end
end
