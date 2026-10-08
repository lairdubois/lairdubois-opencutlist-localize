# The interface language chosen by the user (fr / en)
class LocalesController < ApplicationController
  def update
    locale = params[:locale].to_s
    current_user.update!(locale: locale) if I18n.available_locales.map(&:to_s).include?(locale)
    redirect_back_or_to root_path
  end
end
