class LoginMailer < ApplicationMailer
  def link(user)
    @user = user
    @url = login_url(token: user.generate_token_for(:login))
    recipient_locale(user) { mail to: user.email }
  end
end
