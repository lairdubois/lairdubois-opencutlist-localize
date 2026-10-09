class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("OCL_MAIL_FROM", "OpenCutList Localize <noreply@lairdubois.fr>")
  layout "mailer"

  private

  def recipient_locale(user, &)
    I18n.with_locale(user.locale.presence || I18n.default_locale, &)
  end
end
