require "digest"

# A translatable string. Its id is stable : the key is a mutable attribute,
# so renaming or moving a key keeps translations, statuses and history.
class Unit < ApplicationRecord
  KEY_FORMAT = /\A[^.\s]+(\.[^.\s]+)*\z/
  # A line of a key's or a branch's note : "@no-translate" takes the key (or the whole branch) out of the
  # translators' work, "@translate" puts it back inside such a branch. The closest one wins.
  DIRECTIVE = /\A\s*@(no-)?translate\s*\z/

  has_many :translations, dependent: :destroy
  has_many :revisions, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :suggestions, dependent: :destroy

  validates :key, presence: true, format: { with: KEY_FORMAT }
  validates :key, uniqueness: { conditions: -> { where(archived_at: nil) } }, unless: :archived?
  validates :source_text, presence: true
  validate :key_not_overlapping_a_branch, unless: :archived?

  before_validation :refresh_source_hash

  default_scope { order(:position) }
  scope :active, -> { where(archived_at: nil) }
  scope :translatable, -> { where(translatable: true) }

  # unit id => { key => fr text } of the $t(key) in each source (tooltips in the text views)
  def self.ref_texts(units)
    keys = units.to_h { |u| [u.id, u.source_text.to_s.scan(/\$t\(([^),\n]+)/).flatten.map(&:strip).uniq] }
    texts = active.where(key: keys.values.flatten.uniq).pluck(:key, :source_text).to_h
    keys.transform_values { |k| texts.slice(*k) }
  end

  # true (@translate), false (@no-translate) or nil (no directive) : the note's last directive line
  def self.directive(note)
    match = note.to_s.lines.reverse_each.lazy.filter_map { |l| l.match(DIRECTIVE) }.first
    match && match[1].nil?
  end

  # Where the directive deciding whether the key is translated comes from : nil (none, translated),
  # :self (its own note) or the path of the branch whose note holds it
  def self.directive_source(key, note, branch_notes)
    return :self unless directive(note).nil?

    parts = key.split(".")
    (parts.size - 1).downto(1).map { |n| parts.first(n).join(".") }.find { |path| !directive(branch_notes[path]).nil? }
  end

  def self.translatable?(key, note, branch_notes)
    source = directive_source(key, note, branch_notes)
    source.nil? || directive(source == :self ? note : branch_notes[source])
  end

  # Recomputes the translatable flag of the active units, under a branch (or the key itself) or all of them
  def self.refresh_translatable!(prefix = nil)
    branch_notes = BranchNote.to_map
    scope = active.reorder(nil)
    scope = scope.where("key = :p OR key LIKE :like ESCAPE '\\'", p: prefix, like: "#{sanitize_sql_like(prefix)}.%") if prefix
    ids = scope.pluck(:id, :key, :note).group_by { |_, key, note| translatable?(key, note, branch_notes) }.transform_values { |rows| rows.map(&:first) }
    ids.each { |value, unit_ids| where(id: unit_ids).update_all(translatable: value) }
  end

  def self.hash_text(text)
    Digest::SHA256.hexdigest(text.to_s)[0, 16]
  end

  def archived?
    archived_at.present?
  end

  private

  # "a.b" cannot be both a string and a branch holding "a.b.c"
  def key_not_overlapping_a_branch
    return if key.blank?

    parts = key.split(".")
    ancestors = (1...parts.size).map { |n| parts.first(n).join(".") }
    others = Unit.active.where.not(id: id)
    if others.where(key: ancestors).exists? || others.where("key LIKE ? ESCAPE '\\'", "#{Unit.sanitize_sql_like(key)}.%").exists?
      errors.add(:key, :overlapping_branch)
    end
  end

  def refresh_source_hash
    self.source_hash = self.class.hash_text(source_text)
  end
end
