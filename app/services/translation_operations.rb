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

    # Contested by an open issue : no approval until it is closed
    reviewed &&= @user.can_review?(language) && !translation.contested?
    unchanged = old_text == text && !translation.outdated?
    status = if reviewed then :approved
    elsif unchanged then translation.status
    else :translated
    end
    translation.assign_attributes(text: text, source_hash: unit.source_hash, status: status)
    return translation unless translation.changed?

    translation.save!
    record(unit, language, reviewed ? "review" : "translate", old_text, text)
    translation
  end

  # An admin's correction of the text alone (key page) : the status and the fr text it was checked against are kept
  # (approved stays approved, outdated stays outdated). A new or blank text goes through save.
  def correct(unit, language, text)
    translation = unit.translations.find_by(language: language)
    return save(unit, language, text) if translation.nil? || text.to_s.strip.empty?

    old_text = translation.text
    translation.text = text.to_s.gsub("\r\n", "\n")
    return translation unless translation.changed?

    translation.save!
    # The history tints a revision by the status it produced : an approved one stays so
    record(unit, language, translation.approved? ? "review" : "translate", old_text, translation.text)
    translation
  end

  # A text brought by a language's yml (TranslationFileImport), the user being its translator : translated (a
  # reviewed one too), taken as written against the current fr text
  def import(unit, language, text)
    translation = unit.translations.find_or_initialize_by(language: language)
    old_text = translation.text
    translation.update!(text: text, source_hash: unit.source_hash, status: :translated)
    record(unit, language, "import", old_text, text)
    translation
  end

  # An admin renames a target language : its name here and its _label, the name OCL shows. False on a blank name
  def rename_language(language, name)
    name = name.to_s.squish
    return false if name.empty?

    Language.transaction do
      language.update!(name: name)
      unit = Unit.active.find_by(key: Language::LABEL_KEY)
      correct(unit, language, name) if unit
    end
    true
  end

  private

  def record(unit, language, kind, old_value, new_value)
    unit.revisions.create!(kind: kind, language: language, old_value: old_value, new_value: new_value, author: @user.name, user: @user)
    sync_language_name(unit, language, new_value)
  end

  # A translated _label is the language's name ; removing it leaves the name as it is
  def sync_language_name(unit, language, text)
    return unless unit.key == Language::LABEL_KEY

    name = text.to_s.squish
    language.update!(name: name) if name.present?
  end
end
