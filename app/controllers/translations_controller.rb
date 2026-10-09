# The translator's editor : fr source, en reference and the target language side by side
class TranslationsController < ApplicationController
  include ListFilters

  PER_PAGE = 40
  # fr source revisions (no language) counting as a change for every language, in the sort by date
  SOURCE_KINDS = %w[import create source_minor source_major].freeze

  before_action :set_language
  before_action :set_reference, only: [:index]
  before_action :set_unit, only: [:update, :history]
  before_action :require_admin, only: [:history]

  # Asks Claude for suggestions on the untranslated or outdated strings of the current page
  def pretranslate
    ids = params.require(:unit_ids).map(&:to_i)
    PretranslateJob.perform_later(@language.id, ids)
    redirect_back_or_to translate_path(@language.code), notice: t(".started", count: ids.size)
  end

  def index
    searched = searched_units
    # The user filter offers who worked on this language
    @users = Revision.where(language: @language).users.to_a | [list_query.user].compact
    # A single index drops the other filters when applied (ListFilters) and they drop it :
    # the menu's counts leave it out
    @counts = filter_counts(searched)
    searched = filter_by_index(searched) if single_index?
    @count = single_index? ? searched.count : @counts[:list]
    scope = sorted(searched.where(status_condition).where(questions_condition).where(warnings_condition).where(days_condition))
    @page = [params[:page].to_i, 1].max
    @units = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @more = @page * PER_PAGE < @count
    preload_rows(@units)
    # Shown on the rows when sorted by date
    @revised_at = @units.to_h { |u| [u.id, ActiveRecord::Type.lookup(:datetime).deserialize(u.attributes["revised_at"])&.in_time_zone] } if list_sort == "updated"
    # Infinite scroll : the next page is loaded into the lazy frame at the bottom of the list
    render partial: "page_frame" if turbo_frame_request?
  end

  def update
    operations.save(@unit, @language, params[:text], reviewed: params[:reviewed] == "1")
    @ref_texts = Unit.ref_texts([@unit])
    render partial: "editor", locals: { unit: @unit, language: @language, data: preload_language(@language, [@unit]), saved: true }
  end

  # The unit's history in this language, in the row's lazy frame : older texts can refill the editor
  def history
    render partial: "history", locals: { unit: @unit, language: @language, entries: TranslationHistory.new(@unit, @language).entries }
  end

  private

  def set_language
    @language = Language.targets.find_by!(code: params[:lang])
    redirect_to translate_root_path, alert: t("flash.no_language_access") unless current_user.can_translate?(@language)
  end

  # en is shown as a reference unless it is edited on this page ; it becomes the main one on the user's choice
  def set_reference
    en = Language.find_by(code: "en")
    @en = en if en && en != @language
    @en_reference = @en.present? && current_user.reference_language == "en"
  end

  def set_unit
    @unit = Unit.active.find(params[:unit_id])
  end

  def operations
    TranslationOperations.new(current_user)
  end

  # SQL condition of each status, on the units LEFT JOIN translations of the edited language.
  # They partition the units : an outdated translation is neither "unreviewed" nor "reviewed".
  def status_conditions
    up_to_date = "translations.source_hash = units.source_hash"
    {
      "untranslated" => "translations.id IS NULL",
      "outdated" => "translations.source_hash <> units.source_hash",
      "unreviewed" => Unit.sanitize_sql_array(["translations.status = ? AND #{up_to_date}", Translation.statuses[:translated]]),
      "reviewed" => Unit.sanitize_sql_array(["translations.status = ? AND #{up_to_date}", Translation.statuses[:reviewed]])
    }
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

  # In one query : each status's matches with the other filters (shown in the filters menu),
  # the questions', warnings' and periods' ones, the listed units, and the search alone (for the empty list hint)
  def filter_counts(scope)
    conditions = STATUSES.to_h { |key| [key, "(#{status_conditions[key]}) AND (#{questions_condition}) AND (#{warnings_condition}) AND (#{days_condition})"] }
                         .merge("questions" => "(#{status_condition}) AND #{open_question_condition} AND (#{warnings_condition}) AND (#{days_condition})",
                                "warnings" => "(#{status_condition}) AND (#{questions_condition}) AND #{warning_condition} AND (#{days_condition})")
                         .merge(PERIODS.to_h { |days| ["days_#{days}", "(#{status_condition}) AND (#{questions_condition}) AND (#{warnings_condition}) AND #{period_condition(days.to_i)}"] })
                         .merge(list: "(#{status_condition}) AND (#{questions_condition}) AND (#{warnings_condition}) AND (#{days_condition})", searched: "1 = 1")
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
    if params[:q].present?
      like = "%#{Unit.sanitize_sql_like(params[:q])}%"
      if @en_reference
        scope = scope.joins(Unit.sanitize_sql_array(["LEFT JOIN translations refs ON refs.unit_id = units.id AND refs.language_id = ?", @en.id]))
                     .where("units.source_text LIKE :q ESCAPE '\\' OR translations.text LIKE :q ESCAPE '\\' OR refs.text LIKE :q ESCAPE '\\'", q: like)
      else
        scope = scope.where("units.source_text LIKE :q ESCAPE '\\' OR translations.text LIKE :q ESCAPE '\\'", q: like)
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
    return scope if params[:at].blank?

    from, to = index_range
    if from
      first = unit_at_index(from)
      scope = first ? scope.where("(units.position, units.id) >= (?, ?)", first.position, first.id) : scope.none
    end
    if to && (last = unit_at_index(to))
      scope = scope.where("(units.position, units.id) <= (?, ?)", last.position, last.id)
    end
    scope
  end

  def unit_at_index(index)
    Unit.active.reorder(:position, :id).offset(index - 1).first if index.positive?
  end

  def sanitize_join
    Unit.sanitize_sql_array(["LEFT JOIN translations ON translations.unit_id = units.id AND translations.language_id = ?", @language.id])
  end

  # Everything a row needs, in a few queries
  def preload_rows(units)
    ids = units.map(&:id)
    @data = preload_language(@language, units)
    # 1-based index of the key in the flattened tree (positions can have gaps and ties)
    ranked = Unit.active.reorder(nil).select("units.id, ROW_NUMBER() OVER (ORDER BY units.position, units.id) AS idx")
    @indexes = Unit.unscoped.from(ranked, :units).where(id: ids).pluck(:id, :idx).to_h
    @ref_texts = Unit.ref_texts(units)
    @references = @en ? Translation.where(unit_id: ids, language: @en).includes(:unit).index_by(&:unit_id) : {}
    # Previous fr text, to show what changed on an outdated translation
    @previous_sources = Revision.where(unit_id: ids, kind: "source_major").group(:unit_id).maximum(:id)
                                .then { |h| Revision.where(id: h.values).pluck(:unit_id, :old_value).to_h }
  end

  # What one language's editor needs
  def preload_language(language, units)
    ids = units.map(&:id)
    texts = units.map(&:source_text)
    {
      translations: Translation.where(unit_id: ids, language: language).includes(:unit).index_by(&:unit_id),
      machine: Suggestion.where(unit_id: ids, language: language).pluck(:unit_id, :text).to_h,
      comment_counts: Comment.visible_in(language).where(unit_id: ids).group(:unit_id).count,
      open_questions: Comment.open_questions.visible_in(language).where(unit_id: ids).distinct.pluck(:unit_id).to_set,
      # Same fr text already translated elsewhere in this language
      suggestions: Translation.joins(:unit).merge(Unit.active).where(language: language, units: { source_text: texts })
                              .where.not(unit_id: ids).pluck("units.source_text", "translations.text")
                              .group_by(&:first).transform_values { |v| v.map(&:last).uniq.first(3) }
    }
  end
end
