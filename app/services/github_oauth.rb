require "net/http"
require "json"

# GitHub App user authorization : an admin connects their GitHub account and publishes with their own
# user access token, limited to what both they and the App may do (contents and pull requests of the
# repos the App is installed on). Tokens live 8 h and are refreshed with the refresh token (6 months).
class GithubOauth
  def initialize(config = Rails.configuration.x.ocl)
    @config = config
  end

  def enabled?
    @config.github_app_client_id.present? && @config.github_app_client_secret.present?
  end

  def authorize_url(redirect_uri:, state:)
    "#{@config.web_url}/login/oauth/authorize?" +
      { client_id: @config.github_app_client_id, redirect_uri: redirect_uri, state: state }.to_query
  end

  # Exchanges the callback code, and keeps the account only if it may push to the OCL repo
  def connect!(user, code:, redirect_uri:)
    tokens = token_request(code: code, redirect_uri: redirect_uri)
    me = GithubApi.request(:get, "/user", token: tokens["access_token"])
    repo = GithubApi.request(:get, "/repos/#{@config.github_repo}", token: tokens["access_token"])
    raise OclRepo::Error, I18n.t("github_oauth.no_push", login: me["login"], repo: @config.github_repo) unless repo.dig("permissions", "push")

    user.update!(github_id: me["id"], github_login: me["login"], **token_attributes(tokens))
  end

  # Revokes the authorization on GitHub (best effort) and forgets the tokens
  def disconnect!(user)
    token = user.github_access_token
    if token.present?
      GithubApi.request(:delete, "/applications/#{@config.github_app_client_id}/grant",
                        basic: [@config.github_app_client_id, @config.github_app_client_secret], payload: { access_token: token })
    end
  rescue OclRepo::Error => e
    Rails.logger.warn("GitHub grant revocation failed : #{e.message}")
  ensure
    user.forget_github!
  end

  # A valid access token, refreshed when about to expire. Refresh tokens are single use : the row lock
  # keeps two concurrent publications from both spending it.
  def token_for(user)
    user.with_lock do
      expires_at = user.github_token_expires_at
      return user.github_access_token if expires_at.nil? || expires_at > 5.minutes.from_now

      if user.github_refresh_token.blank? || user.github_refresh_token_expires_at&.past?
        raise OclRepo::Error, I18n.t("github_oauth.expired")
      end

      begin
        tokens = token_request(grant_type: "refresh_token", refresh_token: user.github_refresh_token)
      rescue OclRepo::Error => e
        raise OclRepo::Error, I18n.t("github_oauth.revoked", error: e.message)
      end
      user.update!(token_attributes(tokens))
      user.github_access_token
    end
  end

  private

  # Without token expiration enabled on the App, GitHub returns neither expires_in nor a refresh token
  def token_attributes(tokens)
    { github_access_token: tokens["access_token"],
      github_token_expires_at: tokens["expires_in"]&.then { |s| s.to_i.seconds.from_now },
      github_refresh_token: tokens["refresh_token"],
      github_refresh_token_expires_at: tokens["refresh_token_expires_in"]&.then { |s| s.to_i.seconds.from_now } }
  end

  # GitHub answers 200 with an "error" field when the code or refresh token is refused
  def token_request(**params)
    uri = URI("#{@config.web_url}/login/oauth/access_token")
    req = Net::HTTP::Post.new(uri, "Accept" => "application/json")
    req.set_form_data(client_id: @config.github_app_client_id, client_secret: @config.github_app_client_secret, **params)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    body = JSON.parse(res.body) rescue {}
    return body if res.is_a?(Net::HTTPSuccess) && body["access_token"].present?

    raise OclRepo::Error, "GitHub OAuth : #{body['error_description'] || body['error'] || res.code}"
  end
end
