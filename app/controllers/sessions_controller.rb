# Passwordless login : the user receives a single-use link by e-mail
class SessionsController < ApplicationController
  skip_before_action :require_login
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("sessions.rate_limited") }

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user
      mail = LoginMailer.link(user)
      mail.deliver_later
      # No mail server in development : show the link directly
      flash[:dev_login_url] = mail.body.to_s[%r{https?://\S+}] if Rails.env.development?
    end
    # Same answer whether the address is known or not
    redirect_to new_session_path, notice: t(".sent")
  end

  # Opening the link only shows a button : mail scanners and link prefetching
  # follow GET links, and must not burn the single-use token
  def show
    @user = User.find_by_token_for(:login, params[:token])
    redirect_to(new_session_path, alert: t("sessions.invalid_link")) unless @user
  end

  def consume
    user = User.find_by_token_for(:login, params[:token])
    return redirect_to(new_session_path, alert: t("sessions.invalid_link")) unless user

    user.touch # burns the token
    reset_session
    session[:user_id] = user.id
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to new_session_path
  end
end
