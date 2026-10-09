# GitHub push webhook : after a push to the base branch, checks whether its fr.yml needs a sync (RepoFrCheckJob),
# so admins are told to sync
class GithubWebhooksController < ActionController::Base
  skip_forgery_protection

  def create
    secret = Rails.configuration.x.ocl.webhook_secret
    return head :not_found if secret.blank?

    body = request.raw_post
    expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, body)
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Hub-Signature-256"].to_s)
    return head :ok unless request.headers["X-GitHub-Event"] == "push"

    payload = JSON.parse(body)
    sha = payload["after"].to_s
    # Every push, not only those listing a fr.yml change : the payload lists 20 commits at most
    if payload["ref"] == "refs/heads/#{OclRepo.base_branch}" && sha.match?(/\A\h{40}\z/) && sha != "0" * 40
      RepoFrCheckJob.perform_later(sha)
    end
    head :ok
  end
end
