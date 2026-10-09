# Append-only history of everything that happens to a unit
class Revision < ApplicationRecord
  KINDS = %w[import create rename source_minor source_major note translate review archive restore].freeze

  belongs_to :unit
  belongs_to :language, optional: true
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  default_scope { order(:created_at, :id) }

  # Made by a user : in the tool, or imported from Transifex under their username
  scope :by_user, ->(user) {
    imported = "transifex:#{user.transifex_username}" if user.transifex_username.present?
    imported ? where(user_id: user.id).or(where(user_id: nil, author: imported)) : where(user_id: user.id)
  }

  # Users with a revision in the scope (imported ones included), by name
  def self.users
    authors = unscope(:order).where(user_id: nil).where("author LIKE 'transifex:%'").distinct.pluck(:author)
    usernames = authors.map { |a| a.delete_prefix("transifex:") }
    User.where(id: unscope(:order).where.not(user_id: nil).select(:user_id)).or(User.where(transifex_username: usernames)).order(:name)
  end
end
