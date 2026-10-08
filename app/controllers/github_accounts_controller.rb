# Connects an admin's GitHub account (GitHub App user authorization), so their publications are theirs
class GithubAccountsController < ApplicationController
  before_action :require_admin
  before_action :require_oauth

  def connect
    session[:github_oauth_state] = state = SecureRandom.urlsafe_base64(32)
    redirect_to @oauth.authorize_url(redirect_uri: github_callback_url, state: state), allow_other_host: true
  end

  def callback
    state = session.delete(:github_oauth_state)
    return redirect_to publications_path, alert: t(".denied") if params[:error].present?
    unless state.present? && ActiveSupport::SecurityUtils.secure_compare(state, params[:state].to_s)
      return redirect_to publications_path, alert: t(".bad_state")
    end

    @oauth.connect!(current_user, code: params[:code].to_s, redirect_uri: github_callback_url)
    redirect_to publications_path, notice: t(".connected", login: current_user.github_login)
  rescue OclRepo::Error => e
    redirect_to publications_path, alert: t(".failed", error: e.message)
  end

  def disconnect
    @oauth.disconnect!(current_user)
    redirect_to publications_path, notice: t(".disconnected")
  end

  private

  def require_oauth
    @oauth = GithubOauth.new
    redirect_to publications_path, alert: t("github_accounts.not_configured") unless @oauth.enabled?
  end
end
