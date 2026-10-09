# Search bar params shared by the translator's list and the keys list :
#   q          text search, in the texts only
#   status[]   translation statuses, combined with OR (none = every status)
#   questions  "1" : with an open question, combined with AND
#   warnings   "1" : with a TranslationChecks warning, combined with AND
#   days       one of PERIODS : changed (a revision) in the last n days, combined with AND
#   key        substring of the key
#   prefix     branch : the key itself or anything under it
#   user       user id : keys with a revision by them (Revision.by_user)
#   at         index range in the flattened tree (#120, #120-180, #120-, #-180). A single index (#120)
#              is exclusive : it drops every other param above
#   sort       order of the list, where offered (translator's list) : "index" (the default) or "updated"
#              (last revision) ; not a filter, kept by a single index
#   dir        "asc" or "desc", the sort's own direction by default
module ListFilters
  extend ActiveSupport::Concern

  STATUSES = %w[untranslated outdated unreviewed reviewed].freeze
  FIELDS = %w[key prefix user at].freeze
  # Offered periods of the days filter, in days
  PERIODS = %w[1 7 30 90].freeze
  # Each sort, with its default direction
  SORTS = { "index" => "asc", "updated" => "desc" }.freeze

  # The params above, read from a request's params or from a remembered list url
  class Query
    NAMES = ["q", "status", "questions", "warnings", "days", *FIELDS, "sort", "dir"].freeze

    def self.from_url(url)
      new(Rack::Utils.parse_nested_query(URI(url.to_s).query.to_s))
    end

    def initialize(params)
      @values = NAMES.to_h { |name| [name, params[name]] }
      @values = @values.slice("at", "sort", "dir") if single_index?
    end

    def [](name)
      @values[name.to_s].presence
    end

    # ?at=120 : a single key, alone in the list
    def single_index?
      self[:at].is_a?(String) && !self[:at].include?("-")
    end

    def statuses
      @statuses ||= STATUSES & Array(self[:status])
    end

    def questions?
      self[:questions] == "1"
    end

    def warnings?
      self[:warnings] == "1"
    end

    # The picked period, in days (nil when none)
    def days
      self[:days].to_i if PERIODS.include?(self[:days])
    end

    # The picked sort, nil when none (by index)
    def sort
      self[:sort] if SORTS.key?(self[:sort])
    end

    def sort_dir
      %w[asc desc].include?(self[:dir]) ? self[:dir] : SORTS.fetch(sort || "index")
    end

    # Narrowed by a status, the questions or the warnings flag, a period (the search fields aside)
    def filtered?
      statuses.any? || questions? || warnings? || days.present?
    end

    def searched?
      [:q, *FIELDS].any? { |name| self[name].present? }
    end

    def any?
      filtered? || searched?
    end

    # As link params
    def to_params
      { q: self[:q], status: statuses.presence, questions: ("1" if questions?), warnings: ("1" if warnings?), days: days&.to_s }
        .merge(FIELDS.to_h { |name| [name.to_sym, self[name]] }, sort: sort, dir: (sort_dir if sort)).compact
    end

    # The ?user= one, nil when unknown
    def user
      return @user if defined?(@user)

      @user = self[:user] && User.find_by(id: self[:user])
    end

    # Index range in the flattened tree, as [from, to] (nil = open end) : ?at=120 is the key #120 alone,
    # ?at=120-180 a range, ?at=120- from #120 on, ?at=-180 up to #180
    def index_range
      at = self[:at].to_s.delete("#").strip
      from, to = at.split("-", 2).map { |n| n.strip.presence&.to_i }
      at.include?("-") ? [from, to] : [from, from]
    end
  end

  included do
    helper_method :list_params, :statuses, :questions?, :warnings?, :list_days, :list_sort, :list_sort_dir
    before_action :exclusive_index
  end

  private

  def list_query
    @list_query ||= Query.new(params)
  end

  delegate :single_index?, :statuses, :questions?, :warnings?, :filtered?, :searched?, :index_range, to: :list_query, private: true

  def list_days
    list_query.days
  end

  def list_sort
    list_query.sort
  end

  def list_sort_dir
    list_query.sort_dir
  end

  # The search bar reads the params themselves
  def exclusive_index
    return unless single_index?

    [:q, :status, :questions, :warnings, :days, *(FIELDS - ["at"])].each { |name| params.delete(name) }
  end

  # The current list, as link params
  def list_params
    list_query.to_params
  end
end
