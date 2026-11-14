# The translator's editor : fr source, en reference and the target language side by side
class TranslationsController < ApplicationController
  include ListFilters
  include TranslationEditorData

  PER_PAGE = 40
  # fr source revisions (no language) counting as a change for every language, in the sort by date
  SOURCE_KINDS = %w[import create source_minor source_major].freeze
  # SQL condition of each notranslate value (ListFilters::NOTRANSLATE)
  NOTRANSLATE_CONDITIONS = {
    "1" => "units.translatable = FALSE",
    "directive" => "units.translatable = FALSE AND units.copied = FALSE",
    "copied" => "units.copied = TRUE"
  }.freeze

  helper_method :ref_url

  before_action :set_language
  before_action :set_reference, only: [:index]
  before_action :set_unit, only: [:update, :history]
  before_action :require_admin, only: [:history]

  def index
    searched = searched_units
    # The user filter offers who worked on this language
    @users = Revision.where(language: @language).users.to_a | [list_query.user].compact
    # A single index drops the other filters when applied (ListFilters) and they drop it :
    # the menu's counts leave it out
    @counts = filter_counts(searched)
    searched = filter_by_index(searched) if single_index?
    @count = single_index? ? searched.where(translatable_condition).count : @counts[:list]
    scope = sorted(searched.where(translatable_condition).where(filter_conditions.values.join(" AND ")))
    @page = [params[:page].to_i, 1].max
    @units = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @more = @page * PER_PAGE < @count
    preload_rows(@units)
    # Shown on the rows when sorted by date
    @revised_at = @units.to_h { |u| [u.id, ActiveRecord::Type.lookup(:datetime).deserialize(u.attributes["revised_at"])&.in_time_zone] } if list_sort == "updated"
    # Infinite scroll : the next page is loaded into the lazy frame at the bottom of the list
    return render partial: "page_frame" if turbo_frame_request?

    @open_issues = Issue.still_open.visible_to(current_user).where(language: @language).count
    @divergent_duplicates = SourceDuplicates.new(@language, translatable: true).divergent.size
    # The language switch, with each one's progress
    languages = current_user.readable_languages.to_a
    @language_stats = Language.stats(languages) if languages.size > 1
  end

  def update
    # A reader's list is read-only
    return head :forbidden unless current_user.can_translate?(@language)
    # Copied as is into every language : nothing to save (the editor is read-only)
    return head :unprocessable_content if @unit.copied

    operations.save(@unit, @language, params[:text], reviewed: params[:reviewed] == "1")
    @refs = Unit.refs([@unit])
    render partial: "editor", locals: { unit: @unit, language: @language, data: preload_language(@language, [@unit]), saved: true }
  end

  # The unit's history in this language, in the row's lazy frame : older texts can refill the editor
  def history
    render partial: "history", locals: { unit: @unit, language: @language, entries: TranslationHistory.new(@unit, @language).entries }
  end

  private

  def set_language
    @language = Language.targets.find_by!(code: params[:lang])
    redirect_to translate_root_path, alert: t("flash.no_language_access") unless current_user.can_read?(@language)
  end

  # en is shown as a reference unless it is edited on this page ; it becomes the main one on the user's choice
  def set_reference
    en = Language.find_by(code: "en")
    @en = en if en && en != @language
    @en_reference = @en.present? && current_user.reference_language == "en"
  end

  # A $t() key, alone in this language's list : none for a translator when out of their work
  def ref_url(ref)
    translate_path(@language.code, at: ref.index) if ref.translatable || current_user.admin?
  end

  # Keys out of the translators' work (@no-translate, copied) : admins only
  def set_unit
    @unit = (current_user.admin? ? Unit.active : Unit.active.translatable).find(params[:unit_id])
  end

  # The keys out of the translators' work instead of the others : an admin's filter
  def notranslate?
    current_user.admin? && list_query.notranslate?
  end

  # Admin notes : an admin's filter
  def admin_notes?
    current_user.admin? && list_query.admin_notes?
  end

  # The translators' keys, or (notranslate) the picked kind of the others. An admin's single index shows its key either way.
  def translatable_condition
    return "1 = 1" if single_index? && current_user.admin?

    notranslate? ? NOTRANSLATE_CONDITIONS.fetch(list_query.notranslate) : "units.translatable = TRUE"
  end

  def operations
    TranslationOperations.new(current_user)
  end

  # SQL condition of each status, on the units LEFT JOIN translations of the edited language.
  # They partition the units : a translation to review (outdated, or contested by an open issue) is neither
  # "not_approved" nor "approved". A copied unit has none (its translations are left out of the export).
  def status_conditions
    up_to_date = "NOT #{Translation.to_review_sql}"
    {
      "not_translated" => "translations.id IS NULL",
      "outdated" => Translation.to_review_sql,
      "not_approved" => Unit.sanitize_sql_array(["translations.status = ? AND #{up_to_date}", Translation.statuses[:translated]]),
      "approved" => Unit.sanitize_sql_array(["translations.status = ? AND #{up_to_date}", Translation.statuses[:approved]])
    }.transform_values { |sql| "units.copied = FALSE AND #{sql}" }
  end

  # Checked statuses, OR-ed (none = every unit)
  def status_condition
    statuses.any? ? statuses.map { |key| "(#{status_conditions[key]})" }.join(" OR ") : "1 = 1"
  end

  def open_question_condition
    "units.id IN (#{Comment.open_questions.visible_in(@language).select(:unit_id).to_sql})"
  end

  def questions_condition
    questions? ? open_question_condition : "1 = 1"
  end

  def open_issue_condition
    "units.id IN (#{Issue.still_open.where(language: @language).where.not(unit_id: nil).select(:unit_id).to_sql})"
  end

  def issues_condition
    issues? ? open_issue_condition : "1 = 1"
  end

  # Admin notes for this language or for all of them
  def open_admin_note_condition
    "units.id IN (#{Comment.open_admin_notes.visible_in(@language).select(:unit_id).to_sql})"
  end

  def admin_notes_condition
    admin_notes? ? open_admin_note_condition : "1 = 1"
  end

  # Ids of a few hundred units at most, computed (and cached) by TranslationChecks
  def warning_condition
    @warning_condition ||= TranslationChecks.unit_ids(@language)
                                            .then { |ids| ids.any? ? "units.id IN (#{ids.map(&:to_i).join(',')})" : "1 = 0" }
  end

  def warnings_condition
    warnings? ? warning_condition : "1 = 1"
  end

  # Changed in the last days : a revision in this language or of the fr source (as the sort by date)
  def period_condition(days)
    revised = Revision.unscope(:order).where(created_at: days.days.ago..)
                      .where("revisions.language_id = :language OR (revisions.language_id IS NULL AND revisions.kind IN (:kinds))",
                             language: @language.id, kinds: SOURCE_KINDS)
    "units.id IN (#{revised.select(:unit_id).to_sql})"
  end

  def days_condition
    list_days ? period_condition(list_days) : "1 = 1"
  end

  # The AND-ed filters' conditions, by name
  def filter_conditions
    { status: status_condition, questions: questions_condition, issues: issues_condition, admin_notes: admin_notes_condition,
      warnings: warnings_condition, days: days_condition }.transform_values { |sql| "(#{sql})" }
  end

  # The AND-ed filters, one of them replaced by its own match
  def filters_with(name, sql)
    filter_conditions.merge(name => "(#{sql})").values.join(" AND ")
  end

  # In one query : each status's matches with the other filters (shown in the filters menu),
  # the questions', issues', admin notes' (admins), warnings', notranslate's (admins) and periods' ones, the listed units,
  # and the search alone (for the empty list hint). All of them among the translators' keys or, notranslate, the others.
  def filter_counts(scope)
    others = filter_conditions.values.join(" AND ")
    conditions = STATUSES.to_h { |key| [key, filters_with(:status, status_conditions[key])] }
                         .merge("questions" => filters_with(:questions, open_question_condition),
                                "issues" => filters_with(:issues, open_issue_condition),
                                "warnings" => filters_with(:warnings, warning_condition))
                         .merge(PERIODS.to_h { |days| ["days_#{days}", filters_with(:days, period_condition(days.to_i))] })
    conditions["admin_notes"] = filters_with(:admin_notes, open_admin_note_condition) if current_user.admin?
    conditions = conditions.merge(list: others, searched: "1 = 1")
                           .transform_values { |sql| "(#{sql}) AND #{translatable_condition}" }
    if current_user.admin?
      NOTRANSLATE_CONDITIONS.each { |value, sql| conditions[value == "1" ? "notranslate" : "notranslate_#{value}"] = "#{others} AND #{sql}" }
    end
    counts = scope.reorder(nil).pick(*conditions.values.map { |sql| Arel.sql("COUNT(CASE WHEN #{sql} THEN 1 END)") })
    conditions.keys.zip(counts || Array.new(conditions.size, 0)).to_h
  end

  # Units matching the search text and fields (key, branch, user, index range but a single index),
  # whatever the filters
  def searched_units
    scope = Unit.active.joins(sanitize_join).reorder(:position, :id)
    scope = scope.where("units.key LIKE ? ESCAPE '\\'", "%#{Unit.sanitize_sql_like(params[:key])}%") if params[:key].present?
    scope = scope.where("units.key = :p OR units.key LIKE :like ESCAPE '\\'", p: params[:prefix], like: "#{Unit.sanitize_sql_like(params[:prefix])}.%") if params[:prefix].present?
    if params[:user].present?
      user = list_query.user
      scope = user ? scope.where(units: { id: Revision.unscope(:order).where(language: @language).by_user(user).select(:unit_id) }) : scope.none
    end
    if (text = list_query.text)
      columns = ["units.source_text", "translations.text"]
      if @en_reference
        scope = scope.joins(Unit.sanitize_sql_array(["LEFT JOIN translations refs ON refs.unit_id = units.id AND refs.language_id = ?", @en.id]))
        columns << "refs.text"
      end
      # Exact ("quoted") : instr, case and accents included ; else fold LIKE, both aside
      scope = if list_query.exact?
        scope.where(columns.map { |c| "instr(#{c}, :q) > 0" }.join(" OR "), q: text)
      else
        scope.where(columns.map { |c| "fold(#{c}) LIKE :q ESCAPE '\\'" }.join(" OR "), q: "%#{Unit.sanitize_sql_like(SqliteFold.fold(text))}%")
      end
    end
    single_index? ? scope : filter_by_index(scope)
  end

  # By index (the tree's order), or by last revision in this language or of the fr source ("updated",
  # selected as revised_at for the rows ; keys never revised at the end either way)
  def sorted(scope)
    dir = list_sort_dir == "desc" ? "DESC" : "ASC"
    return scope.reorder(Arel.sql("units.position #{dir}, units.id #{dir}")) unless list_sort == "updated"

    last = Revision.unscope(:order).where("revisions.language_id = :language OR (revisions.language_id IS NULL AND revisions.kind IN (:kinds))",
                                          language: @language.id, kinds: SOURCE_KINDS)
                   .group(:unit_id).select("revisions.unit_id, MAX(revisions.created_at) AS revised_at")
    scope.joins("LEFT JOIN (#{last.to_sql}) last_revisions ON last_revisions.unit_id = units.id")
         .select("units.*, last_revisions.revised_at")
         .reorder(Arel.sql("last_revisions.revised_at #{dir} NULLS LAST, units.position, units.id"))
  end

  def filter_by_index(scope)
    index_ranges.empty? ? scope : scope.where(Unit.index_condition(index_ranges))
  end

  def sanitize_join
    Unit.sanitize_sql_array(["LEFT JOIN translations ON translations.unit_id = units.id AND translations.language_id = ?", @language.id])
  end

  # Everything a row needs, in a few queries
  def preload_rows(units)
    ids = units.map(&:id)
    @data = preload_language(@language, units)
    @glossary = @data[:glossary]
    @indexes = Unit.tree_indexes(ids)
    @refs = Unit.refs(units)
    @references = @en ? Translation.where(unit_id: ids, language: @en).includes(:unit).index_by(&:unit_id) : {}
    # Previous fr text, to show what changed on an outdated translation
    @previous_sources = Revision.where(unit_id: ids, kind: "source_major").group(:unit_id).maximum(:id)
                                .then { |h| Revision.where(id: h.values).pluck(:unit_id, :old_value).to_h }
  end
end
