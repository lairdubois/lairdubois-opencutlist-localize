class Language < ApplicationRecord
  SOURCE_CODE = "fr".freeze

  has_many :translations, dependent: :destroy
  has_many :memberships, dependent: :destroy

  validates :code, presence: true, uniqueness: true

  default_scope { order(:position, :code) }
  scope :targets, -> { where.not(code: SOURCE_CODE) }

  def source?
    code == SOURCE_CODE
  end
end
