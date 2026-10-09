class CommentsController < ApplicationController
  before_action :set_unit_and_language, only: [:index, :create]

  def index
    render partial: "thread", locals: { unit: @unit, language: @language }
  end

  def create
    comment = @unit.comments.create!(user: current_user, body: params.require(:body).strip,
                                     language: @language,
                                     question: @language.present? || params[:question] == "1")
    CommentNotifier.new(comment).call
    render partial: "thread", locals: { unit: @unit, language: @language }
  end

  def resolve
    comment = Comment.find(params[:id])
    return head :forbidden unless current_user.admin? || comment.user == current_user

    comment.update!(resolved_at: Time.current)
    language = Language.find_by(code: params[:lang])
    render partial: "thread", locals: { unit: comment.unit, language: language }
  end

  private

  # lang absent = admin view of every comment
  def set_unit_and_language
    @unit = Unit.find(params[:unit_id])
    @language = Language.find_by(code: params[:lang]) if params[:lang].present?
    allowed = @language ? current_user.can_translate?(@language) : current_user.admin?
    head :forbidden unless allowed
  end
end
