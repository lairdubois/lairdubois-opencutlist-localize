# Writes the i18n-src YAML files into OCL_I18N_EXPORT_DIR (the OCL repo's yaml/i18n-src for now)
class ExportsController < ApplicationController
  before_action :require_admin
  def create
    dir = ENV["OCL_I18N_EXPORT_DIR"]
    return redirect_to(units_path, alert: t(".no_dir")) if dir.blank?

    paths = YamlExport.new.write(dir)
    redirect_to units_path, notice: t(".written", count: paths.size, dir: dir)
  end
end
