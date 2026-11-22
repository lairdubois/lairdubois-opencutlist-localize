class Language < ApplicationRecord
  SOURCE_CODE = "fr".freeze
  # OCL's fallback (gulp) and the translators' other reference : never deleted, nor the source
  FALLBACK_CODE = "en".freeze
  # The key holding each language's own name in OCL, kept in step with #name (TranslationOperations)
  LABEL_KEY = "_label".freeze
  # ISO 639-1 codes offered for a new language : { "de" => { "name" => "Deutsch", "rtl" => false } }
  ISO = YAML.load_file(Rails.root.join("config/iso_languages.yml")).freeze

  has_many :translations, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :issues, dependent: :destroy
  has_many :glossary_entries, dependent: :destroy
  has_many :glossary_revisions, dependent: :destroy
  # Deleted with it, not nullified : language nil means every language (comments) or the fr source (revisions)
  has_many :comments, dependent: :delete_all
  has_many :revisions, dependent: :delete_all
  has_many :suggestions, dependent: :delete_all
  has_many :help_requests, dependent: :nullify

  validates :code, presence: true, uniqueness: true

  # ISO codes not yet a language, by name
  def self.new_codes
    (ISO.keys - unscoped.pluck(:code)).sort_by { |code| SqliteFold.fold(ISO[code]["name"]) }
  end

  # A language of the ISO list (VolunteerRequest#accept!, languages#create), named and oriented from it, last
  def self.create_from_iso!(code)
    create!(code: code, name: ISO.dig(code, "name") || code, rtl: ISO.dig(code, "rtl") || false,
            position: unscoped.maximum(:position).to_i + 1)
  end

  default_scope { order(:position, :code) }
  scope :targets, -> { where.not(code: SOURCE_CODE) }

  # Progress of each language over the translators' keys (the @no-translate ones left out) :
  # { language => { translated:, outdated:, approved:, total: } }. outdated = to review (fr changed, or contested by
  # an open issue), never counted as approved
  def self.stats(languages)
    total = Unit.active.translatable.count
    to_review = Translation.to_review_sql
    counts = Translation.joins(:unit).merge(Unit.active.translatable).where(language: languages).group(:language_id)
                        .pluck(:language_id, Arel.sql("COUNT(*)"),
                               Arel.sql("SUM(#{to_review})"),
                               Arel.sql("SUM(translations.status = 1 AND NOT #{to_review})"))
                        .to_h { |id, n, outdated, approved| [id, { translated: n, outdated: outdated.to_i, approved: approved.to_i }] }
    languages.to_h { |l| [l, counts.fetch(l.id, { translated: 0, outdated: 0, approved: 0 }).merge(total: total)] }
  end

  def source?
    code == SOURCE_CODE
  end

  # languages#destroy : with all its work (translations, history, comments, suggestions, issues, glossary, members)
  def deletable?
    [SOURCE_CODE, FALLBACK_CODE].exclude?(code)
  end
end
