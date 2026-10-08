# Leaving Transifex : last import of texts and statuses, then inviting its translators
class MigrationsController < ApplicationController
  before_action :require_admin
  before_action :require_transifex, except: :show

  def show
    @configured = TransifexClient.new.configured?
    @config = Rails.configuration.x.transifex
    @invited = User.where.not(transifex_username: nil).pluck(:transifex_username).to_set
  end

  def analyze
    @reports = TransifexImport.new.analyze
  rescue TransifexClient::Error => e
    redirect_to migration_path, alert: e.message
  end

  def apply
    import = TransifexImport.new
    reports = import.analyze
    import.apply(reports)
    redirect_to migration_path, notice: t(".applied", texts: reports.sum { |r| r.updates.size }, reviews: reports.sum { |r| r.reviews.size })
  rescue TransifexClient::Error => e
    redirect_to migration_path, alert: e.message
  end

  def roster
    @roster = TransifexRoster.new.call
    @invited = User.where.not(transifex_username: nil).index_by(&:transifex_username)
  rescue TransifexClient::Error => e
    redirect_to migration_path, alert: e.message
  end

  # invites[username] = { email:, name: }
  def invite
    roster = TransifexRoster.new.call
    languages = Language.targets.index_by(&:code)
    created = 0
    params.fetch(:invites, {}).to_unsafe_h.each do |username, attrs|
      next if attrs["email"].blank? || !roster.key?(username)

      user = User.find_by(email: attrs["email"].strip.downcase) || User.new(email: attrs["email"], name: attrs["name"].presence || username)
      user.transifex_username = username
      next unless user.save

      roster[username].each do |code, role|
        membership = user.memberships.find_or_initialize_by(language: languages.fetch(code))
        membership.update!(role: membership.reviewer? ? "reviewer" : role)
      end
      LoginMailer.link(user).deliver_later
      created += 1
    end
    redirect_to migration_roster_path, notice: t(".sent", count: created)
  end

  private

  def require_transifex
    redirect_to migration_path, alert: t("migrations.not_configured") unless TransifexClient.new.configured?
  end
end
