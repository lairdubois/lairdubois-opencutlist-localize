# Who hears about a comment : admins and the language's reviewers for a question,
# everyone who already took part in the discussion otherwise. Never the author.
class CommentNotifier
  def initialize(comment)
    @comment = comment
  end

  def call
    recipients.each { |user| CommentMailer.posted(@comment, user).deliver_later }
  end

  def recipients
    users = @comment.unit.comments.visible_in(@comment.language).includes(:user).map(&:user)
    if @comment.question
      users += User.where(admin: true)
      users += User.joins(:memberships).merge(Membership.reviewer).where(memberships: { language_id: @comment.language_id }) if @comment.language
    end
    users.uniq - [@comment.user]
  end
end
