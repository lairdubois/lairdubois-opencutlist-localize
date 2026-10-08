# Discussion about a unit, for one language or for all of them (language nil).
# A question stays open until someone resolves it.
class Comment < ApplicationRecord
  belongs_to :unit
  belongs_to :language, optional: true
  belongs_to :user

  validates :body, presence: true

  default_scope { order(:created_at) }
  scope :visible_in, ->(language) { where(language: [nil, language]) }
  scope :open_questions, -> { where(question: true, resolved_at: nil) }

  def resolved?
    resolved_at.present?
  end
end
