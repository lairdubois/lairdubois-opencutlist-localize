require "digest"

# A translatable string. Its id is stable : the key is a mutable attribute,
# so renaming or moving a key keeps translations, statuses and history.
class Unit < ApplicationRecord
  KEY_FORMAT = /\A[^.\s]+(\.[^.\s]+)*\z/

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

  # unit id => { key => fr text } of the $t(key) in each source (tooltips in the text views)
  def self.ref_texts(units)
    keys = units.to_h { |u| [u.id, u.source_text.to_s.scan(/\$t\(([^),\n]+)/).flatten.map(&:strip).uniq] }
    texts = active.where(key: keys.values.flatten.uniq).pluck(:key, :source_text).to_h
    keys.transform_values { |k| texts.slice(*k) }
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
    if others.where(key: ancestors).exists? || others.where("key LIKE ?", "#{Unit.sanitize_sql_like(key)}.%").exists?
      errors.add(:key, :overlapping_branch)
    end
  end

  def refresh_source_hash
    self.source_hash = self.class.hash_text(source_text)
  end
end
