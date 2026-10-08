# GitHub push webhook : flags that the base branch's fr.yml changed, so admins are told to sync
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
    fr = "#{OclRepo::I18N_SRC}/fr.yml"
    touched = Array(payload["commits"]).any? { |c| (Array(c["added"]) + Array(c["modified"]) + Array(c["removed"])).include?(fr) }
    i18n_bot = Array(payload["commits"]).all? { |c| c.dig("author", "name") == "OCL i18n" }
    if payload["ref"] == "refs/heads/#{Rails.configuration.x.ocl.base_branch}" && touched && !i18n_bot
      Setting["repo_fr_changed_at"] = Time.current.iso8601
    end
    head :ok
  end
end
