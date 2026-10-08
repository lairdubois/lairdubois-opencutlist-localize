class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :language

  enum :role, { translator: 0, reviewer: 1 }

  validates :language_id, uniqueness: { scope: :user_id }
end
