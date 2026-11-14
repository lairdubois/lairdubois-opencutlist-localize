# Downloads a language's yml, as a publication would write it : the languages the user can translate or read, fr too for admins
class ExportsController < ApplicationController
  def index
    @languages = exportable.to_a
    @stats = Language.stats(@languages.reject(&:source?))
  end

  def show
    language = exportable.find_by(code: params[:lang])
    return redirect_to exports_path, alert: t(".not_allowed") unless language

    send_data YamlExport.new.file(language), filename: "#{language.code}.yml", type: "application/yaml; charset=utf-8"
  end

  private

  def exportable
    current_user.admin? ? Language.all : current_user.readable_languages
  end
end
