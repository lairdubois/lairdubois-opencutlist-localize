class Translation < ApplicationRecord
  belongs_to :unit
  belongs_to :language

  enum :status, { translated: 0, reviewed: 1 }

  validates :text, presence: true
  validates :language_id, uniqueness: { scope: :unit_id }

  # The fr text changed since this translation was written (and the change was not declared minor)
  def outdated?
    source_hash.present? && source_hash != unit.source_hash
  end
end
