class CommentsController < ApplicationController
  before_action :set_unit_and_language, only: [:index, :create]

  def index
    render partial: "thread", locals: { unit: @unit, language: @language }
  end

  # kind : "comment" (key page), "question" or "admin_note" (admins only, never a question). A reply (parent_id) takes its question's or note's language
  # and visibility, and is neither.
  def create
    body = params.require(:body).strip
    comment = if params[:parent_id].present?
      parent = thread_comments.find(params[:parent_id])
      return head :unprocessable_content unless parent.takes_replies?

      @unit.comments.create!(user: current_user, body: body, parent: parent, language: parent.language, admin_only: parent.admin_only)
    else
      admin_only = current_user.admin? && params[:kind] == "admin_note"
      @unit.comments.create!(user: current_user, body: body, language: @language, admin_only: admin_only,
                             question: !admin_only && (@language.present? || params[:kind] == "question"))
    end
    CommentNotifier.new(comment).call
    render partial: "thread", locals: { unit: @unit, language: @language, posted: comment }
  end

  def resolve
    comment = Comment.visible_to(current_user).find(params[:id])
    return head :forbidden unless current_user.admin? || comment.user == current_user
    return head :unprocessable_content unless comment.takes_replies?

    comment.update!(resolved_at: Time.current)
    language = Language.find_by(code: params[:lang])
    render partial: "thread", locals: { unit: comment.unit, language: language }
  end

  private

  # lang absent = admin view of every comment
  def set_unit_and_language
    @unit = Unit.find(params[:unit_id])
    @language = Language.find_by(code: params[:lang]) if params[:lang].present?
    # A reader comments too
    allowed = @language ? current_user.can_read?(@language) : current_user.admin?
    head :forbidden unless allowed
  end

  # The comments the thread shows
  def thread_comments
    (@language ? @unit.comments.visible_in(@language) : @unit.comments).visible_to(current_user)
  end
end
