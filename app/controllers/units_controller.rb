class UnitsController < ApplicationController
  include ListFilters

  PER_PAGE = 200

  before_action :require_admin
  before_action :set_unit, only: [:show, :rename, :source, :note, :archive]

  def index
    # Remembered for the "← Keys" link of a key's page (not the frames : branches, next pages,
    # nor Turbo's hover prefetch of a link not clicked)
    session[:units_list_url] = request.fullpath unless turbo_frame_request? || request.headers["X-Sec-Purpose"] == "prefetch"
    @languages = Language.targets.to_a
    list = UnitList.new(list_query, languages: @languages.size)
    @indexes = list.indexes
    return render_branch(UnitTree.new(list.units, list.stats)) if params[:branch].present?

    @counts = list.counts
    units = list.listed
    @tree = UnitTree.new(units, list.stats)
    # Filtered : the tree is shown unfolded, a page of keys at a time (infinite scroll).
    # Otherwise it is folded, and each branch loads its children when opened.
    @open = filtered? || searched?
    return unless @open

    @page = [params[:page].to_i, 1].max
    page_units = units.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
    @more = @page * PER_PAGE < units.size
    @roots = UnitTree.new(page_units, list.stats).complete_from(@tree).roots
    render partial: "page_frame" if turbo_frame_request?
  end

  def show
    # The previous / next of a key leave its list : back to every key
    if params[:unfiltered] && request.headers["X-Sec-Purpose"] != "prefetch"
      session[:units_list_url] = units_path
      return redirect_to(@unit)
    end

    @translations = @unit.translations.includes(:language).index_by(&:language)
    @languages = Language.targets
    @refs = Unit.ref_texts([@unit])[@unit.id]
    return if @unit.archived_at # out of the tree

    # Walked within the keys list the page was opened from (a single index aside : it lists one key)
    query = ListFilters::Query.from_url(units_list_url)
    query = ListFilters::Query.new({}) if query.single_index?
    @list = UnitList.new(query, languages: @languages.size)
    # 1-based index in the flattened tree, and position in the list (nil when the key isn't listed)
    @index = @list.indexes[@unit.id]
    @position = @list.listed.index(@unit)&.succ
    @previous, @next = @list.neighbours(@unit)
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

  def note
    operations.edit_note(@unit, params[:note])
    redirect_to @unit, notice: t(".saved")
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
end
