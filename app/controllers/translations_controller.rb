# The translator's editor : fr source, en reference, one or two target languages side by side
class TranslationsController < ApplicationController
  PER_PAGE = 40
  FILTERS = %w[todo untranslated outdated unreviewed questions all].freeze

  before_action :set_language
  before_action :set_second_language, only: [:index]
  before_action :set_unit, only: [:update]

  # Asks Claude for suggestions on the untranslated or outdated strings of the current page
  def pretranslate
    ids = params.require(:unit_ids).map(&:to_i)
    PretranslateJob.perform_later(@language.id, ids)
    redirect_back_or_to translate_path(@language.code), notice: t(".started", count: ids.size)
  end

  def index
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "todo"
    scope = filtered_units
    @count = scope.count
    @page = [params[:page].to_i, 1].max
    @units = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @more = @page * PER_PAGE < @count
    @languages = [@language, @second_language].compact
    preload_rows(@units)
    # Infinite scroll : the next page is loaded into the lazy frame at the bottom of the list
    render partial: "page_frame" if turbo_frame_request?
  end

  def update
    operations.save(@unit, @language, params[:text], reviewed: params[:reviewed] == "1")
    render partial: "editor", locals: { unit: @unit, language: @language, data: preload_language(@language, [@unit]), saved: true }
  end

  private

  def set_language
    @language = Language.targets.find_by!(code: params[:lang])
    redirect_to translate_root_path, alert: t("flash.no_language_access") unless current_user.can_translate?(@language)
  end

  # Optional second target language edited alongside (?also=xx)
  def set_second_language
    return if params[:also].blank? || params[:also] == @language.code

    language = Language.targets.find_by(code: params[:also])
    @second_language = language if language && current_user.can_translate?(language)
  end

  def set_unit
    @unit = Unit.active.find(params[:unit_id])
  end

  def operations
    TranslationOperations.new(current_user)
  end

  def filtered_units
    scope = Unit.active.joins(sanitize_join).reorder(:position, :id)
    scope = case @filter
            when "untranslated" then scope.where(translations: { id: nil })
            when "outdated" then scope.where("translations.source_hash <> units.source_hash")
            when "unreviewed" then scope.where(translations: { status: Translation.statuses[:translated] })
            when "questions" then scope.where(id: Comment.open_questions.visible_in(@language).select(:unit_id))
            when "todo" then scope.where("translations.id IS NULL OR translations.source_hash <> units.source_hash")
            else scope
            end
    scope = scope.where("units.key = :p OR units.key LIKE :like", p: params[:prefix], like: "#{Unit.sanitize_sql_like(params[:prefix])}.%") if params[:prefix].present?
    if params[:q].present?
      like = "%#{Unit.sanitize_sql_like(params[:q])}%"
      scope = scope.where("units.key LIKE :q OR units.source_text LIKE :q OR translations.text LIKE :q", q: like)
    end
    filter_by_index(scope)
  end

  # ?at=120 starts the list at the key #120 of the flattened tree, ?at=120-180 keeps that range
  def filter_by_index(scope)
    return scope if params[:at].blank?

    from, to = params[:at].to_s.delete("#").split("-", 2).map { |n| n.strip.presence&.to_i }
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
    @data = @languages.to_h { |language| [language.id, preload_language(language, units)] }
    # 1-based index of the key in the flattened tree (positions can have gaps and ties)
    ranked = Unit.active.reorder(nil).select("units.id, ROW_NUMBER() OVER (ORDER BY units.position, units.id) AS idx")
    @indexes = Unit.unscoped.from(ranked, :units).where(id: ids).pluck(:id, :idx).to_h
    en = Language.find_by(code: "en")
    @references = en && @languages.exclude?(en) ? Translation.where(unit_id: ids, language: en).pluck(:unit_id, :text).to_h : {}
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
