# The users page's list (UsersController#index, users/_search_bar), searched, filtered and sorted in memory
# (a few hundred users at most). Params :
#   q         name, e-mail or GitHub login (case and accents aside)
#   role[]    OR-ed : admin, reviewer / translator (in some language, or in the picked one), none (no language, not admin),
#             disabled
#   language  a language code : a membership in it, combined with AND
#   days      ACTIVITIES : a revision (Revision.by_user) in the last n days, or "never"
#   seen      ACTIVITIES : a request (User#last_seen_at, consultation included) in the last n days, or "never"
#   sort      SORTS ("invited" : the last invitation sent) (DEFAULT_SORT by default), dir "asc" or "desc" (the sort's own direction by default) : the search bar's sort menu
#             and the table's column headers (UsersHelper)
class UserList
  ROLES = %w[admin reviewer translator reader none disabled].freeze
  ACTIVITIES = [*ListFilters::PERIODS, "never"].freeze
  # Each sort, with its default direction
  SORTS = { "name" => "asc", "email" => "asc", "languages" => "asc", "activity" => "desc", "seen" => "desc", "contributions" => "desc", "invited" => "desc" }.freeze
  DEFAULT_SORT = "seen"

  # A user's revisions : how many, the last one's date
  Stat = Data.define(:count, :last_at)

  attr_reader :q, :roles, :language, :days, :seen

  def initialize(params)
    @q = params[:q].to_s.strip.presence
    @roles = ROLES & Array(params[:role])
    @language = params[:language].presence && Language.targets.find_by(code: params[:language])
    @days = params[:days] if ACTIVITIES.include?(params[:days])
    @seen = params[:seen] if ACTIVITIES.include?(params[:seen])
    @sort = params[:sort] if SORTS.key?(params[:sort])
    @dir = params[:dir] if %w[asc desc].include?(params[:dir])
  end

  # The sort applied
  def sort_column
    @sort || DEFAULT_SORT
  end

  # The picked sort (its chip), nil for the default one in its own direction : reversed, it is one, so that its chip keeps it
  def sort
    sort_column unless sort_column == DEFAULT_SORT && sort_dir == SORTS.fetch(DEFAULT_SORT)
  end

  def sort_dir
    @dir || SORTS.fetch(sort_column)
  end

  def any_chip?
    roles.any? || language || days || seen || sort
  end

  def filtered?
    roles.any? || language || days || seen
  end

  def users
    @users ||= sorted(all.select { |user| match?(user) })
  end

  # Each menu entry's matches under the other filters (and the search)
  def counts
    @counts ||= {
      **ROLES.to_h { |role| [role, all.count { |user| match?(user, roles: [role]) }] },
      **ACTIVITIES.to_h { |days| ["days_#{days}", all.count { |user| match?(user, days: days) }] },
      **ACTIVITIES.to_h { |seen| ["seen_#{seen}", all.count { |user| match?(user, seen: seen) }] },
      **Language.targets.to_h { |l| [l.code, all.count { |user| match?(user, language: l) }] },
      searched: all.count { |user| match?(user, roles: [], language: nil, days: nil, seen: nil) }
    }
  end

  def stats
    @stats ||= begin
      revisions = Revision.unscope(:order).where.not(user_id: nil).group(:user_id)
      counts, last = revisions.count, revisions.maximum(:created_at)
      all.to_h { |user| [user.id, (Stat.new(counts[user.id], last[user.id]) if counts[user.id])] }
    end
  end

  # Each user's last invitation sent (Invitation), by user id
  def invited_at
    @invited_at ||= Invitation.group(:user_id).maximum(:created_at)
  end

  private

  def all
    @all ||= User.includes(memberships: :language).to_a
  end

  def match?(user, roles: @roles, language: @language, days: @days, seen: @seen)
    return false if @q && [user.name, user.email, user.github_login].compact.none? { |t| SqliteFold.fold(t).include?(folded_q) }
    return false if language && user.memberships.none? { |m| m.language_id == language.id }
    return false if roles.any? && roles.none? { |role| role?(user, role, language) }
    return false unless within?(user.last_seen_at, seen)

    within?(stats[user.id]&.last_at, days)
  end

  # time in the period (ACTIVITIES), or none for "never" ; any without one
  def within?(time, period)
    case period
    when nil then true
    when "never" then time.nil?
    else time.present? && time >= period.to_i.days.ago
    end
  end

  def folded_q
    @folded_q ||= SqliteFold.fold(@q)
  end

  def role?(user, role, language)
    memberships = user.memberships.select { |m| language.nil? || m.language_id == language.id }
    case role
    when "admin" then user.admin?
    when "reviewer" then memberships.any?(&:reviewer?)
    when "translator" then memberships.any?(&:translator?)
    when "reader" then memberships.any?(&:reader?)
    when "none" then !user.admin? && user.memberships.empty?
    when "disabled" then user.disabled?
    end
  end

  # Ties (and users without activity or language, always last) by name
  def sorted(users)
    by_name = users.sort_by { |user| SqliteFold.fold(user.name) }
    return sort_dir == "desc" ? by_name.reverse : by_name if sort_column == "name"

    key = ->(user) {
      case sort_column
      when "email" then SqliteFold.fold(user.email)
      # Codes in alphabetical order, as the column shows them : "de" before "de es" before "es"
      when "languages" then user.memberships.map { |m| m.language.code }.sort.join(" ").presence
      when "activity" then stats[user.id]&.last_at
      when "seen" then user.last_seen_at
      when "contributions" then stats[user.id]&.count
      when "invited" then invited_at[user.id]
      end
    }
    with, without = by_name.partition { |user| key.(user) }
    with = with.each_with_index.sort_by { |user, i| [key.(user), sort_dir == "desc" ? -i : i] }.map(&:first)
    (sort_dir == "desc" ? with.reverse : with) + without
  end
end
