class CommentMailer < ApplicationMailer
  def posted(comment, user)
    @comment = comment
    @url = comment.language ? translate_url(comment.language.code, q: comment.unit.key, filter: "all") : unit_url(comment.unit)
    recipient_locale(user) do
      mail to: user.email, subject: t(comment.question ? ".subject_question" : ".subject_comment", key: comment.unit.key)
    end
  end
end
