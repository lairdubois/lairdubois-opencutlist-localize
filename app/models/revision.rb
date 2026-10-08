# Append-only history of everything that happens to a unit
class Revision < ApplicationRecord
  KINDS = %w[import create rename source_minor source_major translate review archive restore].freeze

  belongs_to :unit
  belongs_to :language, optional: true
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  default_scope { order(:created_at, :id) }
end
