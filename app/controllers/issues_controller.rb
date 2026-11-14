# A language's issues (points raised by a consistency review), for its translators : listed in the keys' order,
# closed (like a GitHub issue) or reopened
class IssuesController < ApplicationController
  STATES = %w[open closed all].freeze
  LIMIT = 500

  before_action :set_language, only: [:index, :unit]

  # state (open by default) ; kind[] (OR-ed), key (contains), prefix (branch), at (index or range, the keys list's),
  # unit, q (the issue, its key's fr and translation, its text as raised ; "…" : exact) : filters, the states' and
  # kinds' counts under the others. A single index is exclusive (the state kept), as on the other lists. Those whose
  # key left the work are left out for a translator
  def index
    scope = set_filters.fetch(@state)
    @kind_counts = scope.group(:kind).count
    scope = scope.where(kind: @kinds) if @kinds.any?
    # The language-wide ones first, then the keys' order
    @issues = scope.includes(:unit, :closed_by)
                   .reorder(Arel.sql("issues.unit_id IS NOT NULL, units.position, units.id, issues.id")).limit(LIMIT).to_a
    unit_ids = @issues.filter_map(&:unit_id).uniq
    @translations = Translation.where(language: @language, unit_id: unit_ids).includes(:unit).index_by(&:unit_id)
    @indexes = Unit.tree_indexes(Unit.active.where(id: unit_ids).ids)
  end

  # A key's open issues, in its row's panel on the translator's page (lazy frame)
  def unit
    unit = (current_user.admin? ? Unit.active : Unit.active.translatable).find(params[:unit_id])
    render partial: "unit", locals: unit_locals(unit, @language)
  end

  def close
    issue = Issue.find(params[:id])
    return head :forbidden unless current_user.can_translate?(issue.language)

    issue.update!(params[:reopen] ? { closed_at: nil, closed_by: nil } : { closed_at: Time.current, closed_by: current_user })
    return render_row(issue) if params[:row] && issue.unit
    return render_card(issue) if params[:card]
    redirect_back_or_to issues_path(issue.language.code)
  end

  private

  # The list's filters (state, query, unit, kinds) and the states' counts under them ; the scopes by state
  def set_filters
    @state = STATES.include?(params[:state]) ? params[:state] : "open"
    @query = ListFilters::Query.new(params)
    @unit = Unit.find_by(id: params[:unit]) if params[:unit].present? && !@query.single_index?
    @kinds = @query.single_index? ? [] : Issue::KINDS & Array(params[:kind])
    # Kept by the tabs and the cards' buttons
    @filters = { q: @query[:q], kind: @kinds.presence, at: @query[:at], key: @query[:key], prefix: @query[:prefix], unit: @unit&.id }.compact_blank
    base = searched(Issue.visible_to(current_user).where(language: @language))
    by_state = { "open" => base.still_open, "closed" => base.closed, "all" => base }
    @counts = by_state.transform_values { |scope| (@kinds.any? ? scope.where(kind: @kinds) : scope).count }
    by_state
  end

  # Resolved or reopened from the issues page : its card and the states' counts follow, the list stays as it is (scroll kept)
  def render_card(issue)
    @language = issue.language
    set_filters
    translation = Translation.find_by(unit_id: issue.unit_id, language: @language) if issue.unit
    index = Unit.tree_indexes(Unit.active.where(id: issue.unit_id).ids)[issue.unit_id] if issue.unit
    render turbo_stream: [
      turbo_stream.replace(issue, partial: "issues/issue", locals: { issue: issue, translation: translation, index: index }),
      turbo_stream.replace("issues_states", partial: "issues/states")
    ]
  end

  def unit_locals(unit, language)
    { unit: unit, language: language, issues: unit.issues.still_open.where(language: language).order(:id).to_a,
      translation: Translation.find_by(unit: unit, language: language), resolved: unit.issues.closed.where(language: language).count }
  end

  # Resolved from a panel (translator's row, key page) : the panel, status, issues button, approval and the key page's counts follow
  def render_row(issue)
    unit, language = issue.unit, issue.language
    locals = unit_locals(unit, language)
    translation = locals[:translation]
    common = { unit: unit, language: language }
    render turbo_stream: [
      turbo_stream.replace("issues_#{unit.id}_#{language.code}", partial: "issues/unit", locals: locals),
      turbo_stream.replace("status_#{unit.id}_#{language.code}", partial: "translations/status", locals: common.merge(translation: translation)),
      turbo_stream.replace("issues_button_#{unit.id}_#{language.code}", partial: "translations/issues_button", locals: common.merge(count: locals[:issues].size)),
      # The key page's language badge and header count, every language's (absent from the translator's page : ignored)
      turbo_stream.replace("unit_status_#{unit.id}_#{language.code}", partial: "units/language_status", locals: common.merge(translation: translation)),
      turbo_stream.replace("unit_issues_count_#{unit.id}", partial: "units/issues_count", locals: { unit: unit, count: unit.issues.still_open.count }),
      turbo_stream.replace("unit_status_counts_#{unit.id}", partial: "units/status_counts",
                                                            locals: { unit: unit, languages: Language.targets, translations: unit.translations_by_language }),
      turbo_stream.replace("review_#{unit.id}_#{language.code}", partial: "translations/review_button",
                                                                 locals: common.merge(translation: translation, contested: locals[:issues].any?))
    ]
  end

  # Issues matching the search fields (unit, key, branch, index, text), whatever the state and kinds. The text : in the issue, the
  # text as raised, its key, fr source and translation in the language ; exact ("quoted") with instr, else fold LIKE
  def searched(scope)
    scope = scope.left_joins(:unit)
    scope = scope.where(unit: @unit) if @unit
    if (key = @query[:key])
      scope = scope.where("units.key LIKE ? ESCAPE '\\'", "%#{Unit.sanitize_sql_like(key)}%")
    end
    if (prefix = @query[:prefix])
      scope = scope.where("units.key = :p OR units.key LIKE :like ESCAPE '\\'", p: prefix, like: "#{Unit.sanitize_sql_like(prefix)}.%")
    end
    scope = by_index(scope) if @query.index_ranges.any?
    return scope unless (text = @query.text)

    scope = scope.joins(Issue.sanitize_sql_array(["LEFT JOIN translations ON translations.unit_id = issues.unit_id AND translations.language_id = ?", @language.id]))
    columns = ["issues.body", "issues.text", "units.key", "units.source_text", "translations.text"]
    if @query.exact?
      scope.where(columns.map { |c| "instr(#{c}, :q) > 0" }.join(" OR "), q: text)
    else
      scope.where(columns.map { |c| "fold(#{c}) LIKE :q ESCAPE '\\'" }.join(" OR "), q: "%#{Unit.sanitize_sql_like(SqliteFold.fold(text))}%")
    end
  end

  # At indexes or between two indexes of the keys list (active keys, in the keys' order), an open end left out : the whole
  # language's issues and archived keys' aside
  def by_index(scope)
    scope.where(units: { archived_at: nil }).where(Unit.index_condition(@query.index_ranges))
  end

  def set_language
    @language = Language.targets.find_by!(code: params[:lang])
    redirect_to translate_root_path, alert: t("flash.no_language_access") unless current_user.can_read?(@language)
  end
end
