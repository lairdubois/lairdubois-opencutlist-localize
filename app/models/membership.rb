class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :language

  # A reader sees the language's work (translator's list, issues, duplicates, export) and comments, nothing more
  enum :role, { translator: 0, reviewer: 1, reader: 2 }

  # The memberships that edit translations (not readers)
  scope :editing, -> { where(role: [:translator, :reviewer]) }

  validates :language_id, uniqueness: { scope: :user_id }
end
