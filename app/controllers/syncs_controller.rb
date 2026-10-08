# Brings fr.yml changes made by developers into the tool : preview the plan, then apply the admin's decisions.
# The fr.yml comes from the repo checkout, or from an upload.
class SyncsController < ApplicationController
  before_action :require_admin

  def new
  end

  def repo
    repo = OclRepo.new
    repo.fetch!
    preview_text(repo.fr_text)
  rescue OclRepo::Error => e
    redirect_to new_sync_path, alert: t(".failed", error: e.message)
  end

  def preview
    preview_text(params.require(:fr_file).read.force_encoding("UTF-8"))
  rescue Psych::SyntaxError => e
    redirect_to new_sync_path, alert: t(".invalid_yaml", error: e.message)
  end

  def apply
    path = upload_path(params.require(:token))
    sync = SourceSync.new(File.read(path), author: current_user)
    sync.apply(sync.plan, renames: params[:renames], majors: params[:majors])
    File.delete(path)
    Setting["repo_fr_changed_at"] = nil
    redirect_to units_path, notice: t(".applied")
  end

  private

  def preview_text(text)
    @token = SecureRandom.hex(8)
    FileUtils.mkdir_p(upload_dir)
    File.write(upload_path(@token), text)
    @plan = SourceSync.new(text, author: current_user).plan
    render :preview
  end

  def upload_dir
    Rails.root.join("tmp", "sync")
  end

  def upload_path(token)
    upload_dir.join("#{token.gsub(/[^0-9a-f]/, '')}.yml")
  end
end
