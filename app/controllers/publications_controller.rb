# Publishing the translations to the OCL repo as a pull request
class PublicationsController < ApplicationController
  before_action :require_admin

  def index
    @publications = Publication.includes(:user).order(id: :desc).limit(20)
    @auth = GithubAuth.new(user: current_user)
    @oauth = GithubOauth.new
    @can_push = OclRepo.new(auth: @auth).can_push?
  end

  def create
    @result = Publisher.new(current_user).call
    case @result.status
    when :needs_sync then redirect_to new_sync_path, alert: t(".needs_sync")
    when :unchanged then redirect_to publications_path, notice: t(".unchanged")
    else render :show
    end
  rescue OclRepo::Error => e
    redirect_to publications_path, alert: t(".failed", error: e.message)
  end
end
