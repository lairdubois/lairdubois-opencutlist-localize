# What translators and reviewers do, each action recorded as a revision
class TranslationOperations
  def initialize(user)
    @user = user
  end

  # Saving a text always (re)validates it against the current fr text.
  # A blank text removes the translation (the string falls back to en in OCL).
  def save(unit, language, text, reviewed: false)
    translation = unit.translations.find_or_initialize_by(language: language)
    old_text = translation.text
    text = text.to_s.gsub("\r\n", "\n")

    if text.strip.empty?
      return translation unless translation.persisted?

      translation.destroy!
      record(unit, language, "translate", old_text, nil)
      return unit.translations.build(language: language)
    end

    reviewed &&= @user.can_review?(language)
    unchanged = old_text == text && !translation.outdated?
    status = if reviewed then :reviewed
             elsif unchanged then translation.status
             else :translated
             end
    translation.assign_attributes(text: text, source_hash: unit.source_hash, status: status)
    return translation unless translation.changed?

    translation.save!
    record(unit, language, reviewed ? "review" : "translate", old_text, text)
    translation
  end

  private

  def record(unit, language, kind, old_value, new_value)
    unit.revisions.create!(kind: kind, language: language, old_value: old_value, new_value: new_value, author: @user.name, user: @user)
  end
end
