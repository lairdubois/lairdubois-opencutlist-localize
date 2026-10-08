class UnitsController < ApplicationController
  PER_PAGE = 200
  FILTERS = %w[all todo untranslated outdated unreviewed questions].freeze

  before_action :require_admin
  before_action :set_unit, only: [:show, :rename, :source, :archive]

  def index
    # Remembered for the "← Keys" link of a key's page (not the frames : branches, next pages,
    # nor Turbo's hover prefetch of a link not clicked)
    session[:units_list_url] = request.fullpath unless turbo_frame_request? || request.headers["X-Sec-Purpose"] == "prefetch"
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "all"
    @languages = Language.targets.to_a
    stats = unit_stats
    # 1-based index of the key in the flattened tree, same as on the translator's page
    units = Unit.active.reorder(:position, :id).to_a
    @indexes = units.each.with_index(1).to_h { |unit, i| [unit.id, i] }
    return render_branch(UnitTree.new(units, stats)) if params[:branch].present?

    units = filter_units(units, stats)
    @tree = UnitTree.new(units, stats)
    # Filtered : the tree is shown unfolded, a page of keys at a time (infinite scroll).
    # Otherwise it is folded, and each branch loads its children when opened.
    @open = @filter != "all" || params.values_at(:q, :prefix, :at).any?(&:present?)
    return unless @open

    @page = [params[:page].to_i, 1].max
    page_units = units.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
    @more = @page * PER_PAGE < units.size
    @roots = UnitTree.new(page_units, stats).complete_from(@tree).roots
    render partial: "page_frame" if turbo_frame_request?
  end

  def show
    @translations = @unit.translations.includes(:language).index_by(&:language)
    @languages = Language.targets
    # 1-based index in the flattened tree (none for an archived key)
    @index = Unit.active.where("(units.position, units.id) <= (?, ?)", @unit.position, @unit.id).count unless @unit.archived_at
  end

  def rename
    operations.rename(@unit, params.require(:key).strip)
    redirect_back_or_to @unit, notice: t(".renamed")
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to @unit, alert: e.record.errors.full_messages.to_sentence
  end

  def source
    operations.edit_source(@unit, params.require(:source_text), major: params[:change] == "major")
    redirect_to @unit, notice: t(params[:change] == "major" ? ".major" : ".minor")
  end

  def archive
    operations.archive(@unit)
    redirect_to units_list_url, notice: t(".archived", key: @unit.key)
  end

  private

  def units_list_url
    session[:units_list_url].presence || units_path
  end
  helper_method :units_list_url

  def set_unit
    @unit = Unit.find(params[:id])
  end

  def operations
    UnitOperations.new(current_author)
  end

  # Children of a folded branch, loaded into its lazy frame when it is opened
  def render_branch(tree)
    node = tree.find(params[:branch]) or return head(:not_found)
    render partial: "branch", locals: { node: node, languages: @languages.size }
  end

  # Filters apply across every target language : "untranslated" = missing in at least one of them
  def filter_units(units, stats)
    size = @languages.size
    units = case @filter
            when "todo" then units.select { |u| stats.dig(u.id, 0).to_i < size || stats.dig(u.id, 1).to_i > 0 }
            when "untranslated" then units.select { |u| stats.dig(u.id, 0).to_i < size }
            when "outdated" then units.select { |u| stats.dig(u.id, 1).to_i > 0 }
            when "unreviewed" then units.select { |u| stats.dig(u.id, 2).to_i > 0 }
            when "questions" then units.select { |u| question_ids.include?(u.id) }
            else units
            end
    if (prefix = params[:prefix].presence)
      units = units.select { |u| u.key == prefix || u.key.start_with?("#{prefix}.") }
    end
    if (q = params[:q].presence&.downcase)
      units = units.select { |u| u.key.downcase.include?(q) || u.source_text.downcase.include?(q) }
    end
    filter_by_index(units)
  end

  # ?at=120 starts the list at the key #120, ?at=120-180 keeps that range
  def filter_by_index(units)
    return units if params[:at].blank?

    from, to = params[:at].to_s.delete("#").split("-", 2).map { |n| n.strip.presence&.to_i }
    units.select { |u| (i = @indexes[u.id]) >= (from || 1) && (to.nil? || i <= to) }
  end

  def question_ids
    Comment.open_questions.distinct.pluck(:unit_id).to_set
  end

  # Per unit id : [translations count, outdated count, not reviewed count]
  def unit_stats
    Translation.joins(:unit).merge(Unit.active).group(:unit_id)
               .pluck(:unit_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(translations.source_hash <> units.source_hash)"),
                      Arel.sql("SUM(translations.status = #{Translation.statuses[:translated].to_i})"))
               .to_h { |id, n, outdated, unreviewed| [id, [n, outdated.to_i, unreviewed.to_i]] }
  end
end
