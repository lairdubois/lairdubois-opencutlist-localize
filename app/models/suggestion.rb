# A machine-proposed translation, waiting for a human to accept or correct it
class Suggestion < ApplicationRecord
  belongs_to :unit
  belongs_to :language

  validates :text, presence: true
end
