# Opens or updates the pull request of the i18n branch
class GithubPulls
  def initialize(config = Rails.configuration.x.ocl, auth: GithubAuth.new(config))
    @config = config
    @auth = auth
  end

  def enabled?
    @auth.configured?
  end

  # Returns the PR html url
  def open_or_update(title:, body:)
    owner = @config.github_repo.split("/").first
    existing = request(:get, "/repos/#{@config.github_repo}/pulls?state=open&head=#{owner}:#{@config.i18n_branch}").first
    pr = if existing
           request(:patch, "/repos/#{@config.github_repo}/pulls/#{existing['number']}", title: title, body: body)
         else
           request(:post, "/repos/#{@config.github_repo}/pulls", title: title, body: body,
                                                                 head: @config.i18n_branch, base: OclRepo.base_branch(@config))
         end
    pr["html_url"]
  end

  private

  def request(verb, path, payload = nil)
    GithubApi.request(verb, path, token: @auth.token, payload: payload)
  end
end
