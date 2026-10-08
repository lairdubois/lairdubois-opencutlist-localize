# Admins invite people and give them languages (translator or reviewer)
class UsersController < ApplicationController
  before_action :require_admin
  before_action :set_user, only: [:edit, :update, :destroy]

  def index
    @users = User.includes(memberships: :language).order(:name)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      save_memberships
      LoginMailer.link(@user).deliver_later if params[:send_link] == "1"
      redirect_to users_path, notice: t(".created", name: @user.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      save_memberships
      redirect_to users_path, notice: t(".updated", name: @user.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    return redirect_to(users_path, alert: t(".self")) if @user == current_user

    @user.destroy
    redirect_to users_path, notice: t(".destroyed", name: @user.name)
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :admin, :locale)
  end

  # roles[<language_id>] = "" | "translator" | "reviewer"
  def save_memberships
    roles = params.fetch(:roles, {}).to_unsafe_h
    Language.targets.each do |language|
      role = roles[language.id.to_s].presence
      membership = @user.memberships.find_by(language: language)
      if role.nil? then membership&.destroy
      elsif Membership.roles.key?(role) then (membership || @user.memberships.build(language: language)).update!(role: role)
      end
    end
  end
end
