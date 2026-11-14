class CommentMailer < ApplicationMailer
  def posted(comment, user)
    @comment = comment
    @url = url_for_recipient(comment, user)
    recipient_locale(user) do
      mail to: user.email, subject: t(subject(comment), key: comment.unit.key)
    end
  end

  private

  # The key page is an admin's : a translator gets their list, on the comment's language or their first one
  def url_for_recipient(comment, user)
    language = comment.language || (user.readable_languages.first unless user.admin?)
    language ? translate_url(language.code, prefix: comment.unit.key) : unit_url(comment.unit)
  end

  def subject(comment)
    if comment.reply? then ".subject_reply"
    elsif comment.question then ".subject_question"
    else ".subject_comment"
    end
  end
end
