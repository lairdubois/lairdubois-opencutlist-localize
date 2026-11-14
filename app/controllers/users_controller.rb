# Admins invite people and give them languages (translator or reviewer)
class UsersController < ApplicationController
  before_action :require_admin
  before_action :set_user, only: [:edit, :update, :destroy, :invite, :history, :disable, :enable]

  HISTORY_PER_PAGE = 50

  def index
    @list = UserList.new(params)
    @languages = Language.targets
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      save_memberships
      InvitationMailer.invite(@user, current_user).deliver_later if params[:send_invitation] == "1"
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

  # The user's revisions, newest first : a page per lazy frame, the next one
  # chained at its bottom. Filters : language = a code, the source's for the revisions without one (fr, keys),
  # kind = Revision::KINDS. The first page lists each filter's entries, counted under the other filter
  def history
    @page = [params[:page].to_i, 1].max
    @language = params[:language].presence
    @kind = params[:kind].presence
    all = Revision.by_user(@user).unscope(:order)
    by_language = history_language(all, @language)
    by_kind = @kind ? all.where(kind: @kind) : all
    if @page == 1
      @language_counts = history_language_counts(all, by_kind)
      kinds = all.distinct.pluck(:kind)
      counts = by_language.group(:kind).count
      @kind_counts = Revision::KINDS.select { |k| kinds.include?(k) }.map { |k| [k, counts[k] || 0] }
    end
    filtered = @kind ? by_language.where(kind: @kind) : by_language
    revisions = filtered.order(created_at: :desc, id: :desc).includes(:unit, :language)
                        .offset((@page - 1) * HISTORY_PER_PAGE).limit(HISTORY_PER_PAGE + 1).to_a
    @more = revisions.size > HISTORY_PER_PAGE
    @entries = revisions.first(HISTORY_PER_PAGE).map { |r| TranslationHistory.entry(r) }
    render partial: "history"
  end

  # Re-sends the invitation, e.g. when the first one got lost
  def invite
    return redirect_to(edit_user_path(@user), alert: t(".disabled")) unless ActionMailer::Base.perform_deliveries
    return redirect_to(edit_user_path(@user), alert: t(".user_disabled")) if @user.disabled?

    InvitationMailer.invite(@user, current_user).deliver_later
    redirect_to edit_user_path(@user), notice: t(".sent", email: @user.email)
  end

  # Disabling keeps the user (memberships, history) but ends their access : see User.enabled
  def disable
    return redirect_to(edit_user_path(@user), alert: t(".self")) if @user == current_user

    @user.update!(disabled_at: Time.current)
    redirect_to edit_user_path(@user), notice: t(".disabled", name: @user.name)
  end

  def enable
    @user.update!(disabled_at: nil)
    redirect_to edit_user_path(@user), notice: t(".enabled", name: @user.name)
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

  def history_language(scope, code)
    if code == Language::SOURCE_CODE then scope.where(language_id: nil)
    elsif code then scope.where(language_id: Language.where(code: code).select(:id))
    else scope
    end
  end

  # [[code, count]] : the source first (revisions without a language), then by language position
  def history_language_counts(all, filtered)
    ids = all.distinct.pluck(:language_id)
    counts = filtered.group(:language_id).count
    languages = Language.where(id: ids.compact).index_by(&:id)
    ids.sort_by { |id| id ? [1, languages[id].position, languages[id].code] : [0] }
       .map { |id| [id ? languages[id].code : Language::SOURCE_CODE, counts[id] || 0] }
  end

  def user_params
    params.require(:user).permit(:name, :email, :admin, :locale)
  end

  # roles[<language_id>] = "" | "reader" | "translator" | "reviewer". An admin has every language : none kept (the form hides them)
  def save_memberships
    return @user.memberships.destroy_all if @user.admin?

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
