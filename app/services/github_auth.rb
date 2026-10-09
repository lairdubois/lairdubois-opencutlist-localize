require "openssl"
require "base64"
require "monitor"

# Credentials for GitHub : the user access token of an admin who connected their account (GithubOauth),
# else short-lived installation tokens of the OCL Localize GitHub App when it is configured (pushes, PRs
# and commits then show as <app>[bot]), else the static OCL_GITHUB_TOKEN
class GithubAuth
  DEFAULT_COMMITTER = ["OCL Localize", "opencutlist@lairdubois.fr"].freeze

  LOCK = Monitor.new
  CACHE = {} # rubocop:disable Style/MutableConstant -- per-process token cache

  def initialize(config = Rails.configuration.x.ocl, user: nil)
    @config = config
    @oauth = GithubOauth.new(config)
    @user = user if user&.github_connected? && @oauth.enabled?
  end

  # Acting as the admin's own GitHub account
  def user?
    @user.present?
  end

  def login
    @user&.github_login
  end

  def app?
    @config.github_app_id.present? && @config.github_app_private_key.present?
  end

  def configured?
    user? || app? || @config.github_token.present?
  end

  # nil when nothing is configured
  def token
    return @oauth.token_for(@user) if user?
    return @config.github_token.presence unless app?

    LOCK.synchronize do
      cached = CACHE[[:token, @config.github_repo]]
      return cached[:token] if cached && cached[:expires_at] > 5.minutes.from_now

      installation = GithubApi.request(:get, "/repos/#{@config.github_repo}/installation", token: jwt)
      res = GithubApi.request(:post, "/app/installations/#{installation['id']}/access_tokens", token: jwt,
                              payload: { repositories: [@config.github_repo.split("/").last],
                                         permissions: { contents: "write", pull_requests: "write" } })
      CACHE[[:token, @config.github_repo]] = { token: res["token"], expires_at: Time.iso8601(res["expires_at"]) }
      res["token"]
    end
  end

  # [name, email] of the commits : the admin's or the App's bot user noreply address, so GitHub links them
  def committer
    return [@user.name, "#{@user.github_id}+#{@user.github_login}@users.noreply.github.com"] if user?
    return DEFAULT_COMMITTER unless app?

    LOCK.synchronize do
      CACHE[[:committer, @config.github_app_id]] ||= begin
        login = "#{GithubApi.request(:get, '/app', token: jwt)['slug']}[bot]"
        id = GithubApi.request(:get, "/users/#{ERB::Util.url_encode(login)}", token: token)["id"]
        [login, "#{id}+#{login}@users.noreply.github.com"]
      end
    end
  end

  private

  # App authentication, valid 10 minutes at most (iat backdated against clock drift)
  def jwt
    now = Time.now.to_i
    segments = [{ alg: "RS256", typ: "JWT" }, { iat: now - 60, exp: now + 540, iss: @config.github_app_id }]
               .map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }
    signature = private_key.sign("SHA256", segments.join("."))
    [*segments, Base64.urlsafe_encode64(signature, padding: false)].join(".")
  end

  # The PEM itself (literal \n accepted, for single-line env files) or a path to it
  def private_key
    pem = @config.github_app_private_key
    pem = pem.include?("BEGIN") ? pem.gsub('\n', "\n") : File.read(pem)
    OpenSSL::PKey::RSA.new(pem)
  end
end
