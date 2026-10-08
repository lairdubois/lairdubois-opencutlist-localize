class User < ApplicationRecord
  # Main reference in the translator's editor : the fr source, or the en translation for non-French speakers
  REFERENCE_LANGUAGES = %w[fr en].freeze

  has_many :memberships, dependent: :destroy
  has_many :languages, through: :memberships
  has_many :revisions, dependent: :nullify

  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :reference_language, inclusion: { in: REFERENCE_LANGUAGES }

  # Admins' GitHub user access tokens (GithubOauth)
  encrypts :github_access_token, :github_refresh_token

  # Single use : the token dies as soon as the user logs in (last_login_at changes)
  generates_token_for :login, expires_in: 30.minutes do
    updated_at.to_f
  end

  def github_connected?
    github_access_token.present?
  end

  def forget_github!
    update!(github_id: nil, github_login: nil, github_access_token: nil, github_token_expires_at: nil,
            github_refresh_token: nil, github_refresh_token_expires_at: nil)
  end

  def can_translate?(language)
    admin? || memberships.exists?(language: language)
  end

  def can_review?(language)
    admin? || memberships.reviewer.exists?(language: language)
  end

  def editable_languages
    admin? ? Language.targets : languages.merge(Language.targets)
  end
end
