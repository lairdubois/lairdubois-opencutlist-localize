# The glossary, read by everyone : the fr terms, created and edited by the admins, and the term each language expects,
# set by its reviewers (GlossaryOperations, every change in the term's history). A table : the fr terms down, the
# user's languages across (every target for an admin ; en for everyone, read only unless a reviewer), a cell's detail and edit form in a side panel (cell /
# save_cell ; the fr term's : source / save_source, admins ; a new one : new_source / create_source, admins)
class GlossaryController < ApplicationController
  before_action :set_languages
  before_action :require_admin, only: [:archive, :restore, :destroy, :save_source, :new_source, :create_source]
  before_action :set_term, except: [:index, :new_source, :create_source]
  before_action :set_cell_language, only: [:cell, :save_cell]

  def index
    load_list
  end

  def archive
    operations.archive_term(@term)
    redirect_to glossary_path(**column_params), notice: t(".archived", term: @term.term)
  end

  def restore
    operations.restore_term(@term)
    if @term.errors.any?
      redirect_to glossary_path(**column_params, archived: 1), alert: @term.errors.full_messages.to_sentence
    else
      redirect_to glossary_path(**column_params), notice: t(".restored", term: @term.term)
    end
  end

  # An archived term deleted for good, its entries and history with it ; an active one is archived first
  def destroy
    return redirect_to(glossary_path(**column_params), alert: t(".not_archived")) unless @term.archived?

    operations.delete_term(@term)
    redirect_to glossary_path(**column_params, archived: (1 if GlossaryTerm.where.not(archived_at: nil).exists?)),
                notice: t(".deleted", term: @term.term)
  end

  # The side panel : a term in a language (code, one of the user's), its entry's edit form (edit=1) for the
  # language's reviewers
  def cell
    edit = params[:edit] == "1"
    return head :forbidden if edit && !cell_editable?

    render_cell(form: edit)
  end

  # Saves the entry from the side panel : the panel, the cell and its column's header in streams. A term added (none
  # before) goes on to the next shown column without one the user reviews : its form in the panel, its cell selected
  def save_cell
    return head :forbidden unless cell_editable?

    added = !@term.entries.find_by(language: @cell_language)&.term
    entry = operations.save_entry(@term, @cell_language, params.require(:glossary_entry).permit(*GlossaryEntry::FIELDS))
    return render_cell(form: true, entry: entry, status: :unprocessable_content) if entry.errors.any?

    set_columns
    saved = @cell_language
    following = (added && entry.term && next_missing_column(saved)) || nil
    @cell_language = following if following
    render turbo_stream: [
      turbo_stream.update("glossary_panel", partial: "cell_panel", locals: cell_locals(form: following.present?)),
      turbo_stream.replace(helpers.dom_id(@term, "cell_#{saved.code}"),
                           partial: "cell", locals: { term: @term, language: saved, entry: entry.persisted? ? entry : nil, selected: !following }),
      *([turbo_stream.replace(helpers.dom_id(@term, "cell_#{following.code}"),
                              partial: "cell", locals: { term: @term, language: following, entry: @term.entries.find_by(language: following), selected: true })] if following),
      turbo_stream.replace("glossary_column_#{saved.code}", partial: "column", locals: { language: saved, stats: column_stats([saved])[saved.id] })
    ]
  end

  # The side panel on the fr term : its definition, its edit form (edit=1) for the admins
  def source
    edit = params[:edit] == "1"
    return head :forbidden if edit && !current_user.admin?

    render_panel("source_panel", { term: @term, form: edit })
  end

  # Saves the fr term from the side panel : the panel, the term's row (kept as is or not) and the columns' headers
  # (their totals) in streams
  def save_source
    operations.update_term(@term, term_params)
    return render_panel("source_panel", { term: @term, form: true }, status: :unprocessable_content) if @term.errors.any?

    set_columns
    @matrix = { @term.id => @term.entries.index_by(&:language_id) }
    render turbo_stream: [
      turbo_stream.update("glossary_panel", partial: "source_panel", locals: { term: @term, form: false }),
      turbo_stream.replace(helpers.dom_id(@term, :row), partial: "row", locals: { term: @term, selected: Language::SOURCE_CODE }),
      *column_header_streams
    ]
  end

  # The side panel : a new fr term's form, the languages filled afterwards in their cells
  def new_source
    render_panel("new_term_panel", { term: GlossaryTerm.new })
  end

  # Creates the fr term from the side panel : its panel (the first shown column's form when the term is to translate
  # there, else the fr term's), the list's count under the page's filters (list_params), its row when it matches them
  # (put in its place by glossary_table_controller) and the columns' headers in streams
  def create_source
    @term = operations.create_term(term_params)
    return render_panel("new_term_panel", { term: @term }, status: :unprocessable_content) unless @term.persisted?

    load_list
    listed = @terms.include?(@term)
    @cell_language = @columns.first
    @cell_language = nil unless @cell_language && cell_editable?
    panel = @cell_language ? { partial: "cell_panel", locals: cell_locals(form: true) } : { partial: "source_panel", locals: { term: @term, form: false } }
    render turbo_stream: [
      turbo_stream.update("glossary_panel", **panel),
      turbo_stream.update("glossary_count", t("glossary.search_bar.count", count: @counts[:list])),
      *([turbo_stream.append("glossary_grid", partial: "row", locals: { term: @term, selected: @cell_language&.code || Language::SOURCE_CODE }),
         turbo_stream.remove("glossary_empty")] if listed),
      *column_header_streams
    ]
  end

  # The term's history in the side panel's lazy frame. code : fr, the fr term's changes alone ; one of the user's
  # languages, the fr term's and its entry's
  def history
    revisions = @term.revisions.includes(:user, :language)
    if params[:code] == Language::SOURCE_CODE
      revisions = revisions.where(language: nil)
    else
      language = @languages.find { |l| l.code == params[:code] } or return head :not_found
      revisions = revisions.where(language: [nil, language])
    end
    render partial: "history", locals: { term: @term, revisions: revisions.to_a.reverse }
  end

  private

  # The table's columns : the user's languages (every target for an admin, @own_languages) and en, the fallback
  # reference, offered to everyone (read only : cell_editable? needs a reviewer)
  def set_languages
    @own_languages = current_user.readable_languages.to_a
    en = Language.find_by(code: Language::FALLBACK_CODE)
    @languages = (en.nil? || @own_languages.include?(en)) ? @own_languages : [en, *@own_languages]
  end

  def set_term
    @term = GlossaryTerm.find(params[:id])
  end

  def set_cell_language
    @cell_language = @languages.find { |l| l.code == params[:code] } or head :not_found
  end

  def cell_editable?
    !@term.archived? && !@term.no_translate && current_user.can_review?(@cell_language)
  end

  # The first shown column after language whose entry has no term yet, the user one of its reviewers
  def next_missing_column(language)
    filled = @term.entries.where.not(term: nil).pluck(:language_id)
    @columns.drop_while { |l| l != language }.drop(1)
            .find { |l| filled.exclude?(l.id) && current_user.can_review?(l) }
  end

  def cell_locals(form:, entry: nil)
    { term: @term, language: @cell_language, entry: entry || @term.entries.find_by(language: @cell_language),
      form: form, editable: cell_editable? }
  end

  def render_cell(form:, entry: nil, status: :ok)
    render_panel("cell_panel", cell_locals(form: form, entry: entry), status: status)
  end

  # The shown columns' headers, their totals changed
  def column_header_streams
    stats = column_stats(@columns)
    @columns.map { |l| turbo_stream.replace("glossary_column_#{l.code}", partial: "column", locals: { language: l, stats: stats[l.id] }) }
  end

  # A side panel's partial in its frame (a link's or a form's answer)
  def render_panel(partial, locals, status: :ok)
    panel = render_to_string(partial: partial, locals: locals)
    render html: helpers.turbo_frame_tag("glossary_panel") { panel }, status: status
  end

  # The columns : the user's languages and en (@all_columns) ; cols[] : the picked ones only (@picked, codes), in their order
  # (dragged chips or headers : column_order_controller). The choice is the user's (User#glossary_columns) : saved when
  # it comes from the search bar (cols_set=1, none checked : all of them), used when the URL holds none (a link's cols,
  # e.g. the translator's toolbar's, is shown without being saved). None picked : the user's own languages (en only
  # when picked, unless it is one of them), all of them when the user has none
  def set_columns
    @all_columns = @languages
    codes = @all_columns.map(&:code)
    if params[:cols_set] == "1"
      @picked = Array(params[:cols]).map(&:to_s) & codes
      saved = @picked.join(",").presence
      current_user.update_column(:glossary_columns, saved) if saved != current_user.glossary_columns
    else
      @picked = (params.key?(:cols) ? Array(params[:cols]).map(&:to_s) : current_user.glossary_columns.to_s.split(",")) & codes
    end
    @columns = @picked.empty? ? @own_languages.presence || @all_columns : @picked.map { |code| @all_columns.find { |l| l.code == code } }
  end

  # The column choice, carried by the cells' links and the side panel's
  def column_params
    request.query_parameters.slice("cols").symbolize_keys
  end
  helper_method :column_params

  # The columns and the search bar's filters, carried by the new term's form : its answer counts the list under them
  def list_params
    request.query_parameters.slice("cols", "q", "missing", "no_translate").symbolize_keys
  end
  helper_method :list_params

  # A column's progress : its entries with a term over the active terms to translate (kept as is aside)
  # { language id => { filled:, total: } }
  def column_stats(languages)
    terms = GlossaryTerm.active.where(no_translate: false)
    filled = GlossaryEntry.where.not(term: nil).where(glossary_term_id: terms.select(:id), language: languages).group(:language_id).count
    total = terms.count
    languages.to_h { |l| [l.id, { filled: filled.fetch(l.id, 0), total: total }] }
  end

  def term_params
    params.require(:glossary_term).permit(*GlossaryTerm::FIELDS)
  end

  def operations
    GlossaryOperations.new(current_user)
  end

  # The terms in alphabetical order, case and accents aside, through the search bar's filters : q searches them, their
  # definition and the shown columns' entries ; missing=1 : without an expected term in a shown column (the ones kept as
  # is aside) ; no_translate=1 : the ones kept as is ; archived=1 (admins) : the archived ones instead. @counts : each
  # filter's matches under the others (the menu), :list the listed ones
  def load_list
    @archived = current_user.admin? && params[:archived] == "1"
    @missing = params[:missing] == "1"
    @no_translate = params[:no_translate] == "1"
    set_columns
    all = GlossaryTerm.all.to_a
    @matrix = GlossaryEntry.where(glossary_term_id: all.map(&:id), language: @all_columns)
                           .group_by(&:glossary_term_id).transform_values { |entries| entries.index_by(&:language_id) }
    list = lambda do |**filters|
      filter_terms(searched_terms(all, @columns), languages: @columns,
                   **{ archived: @archived, missing: @missing, no_translate: @no_translate }.merge(filters))
    end
    @counts = {
      list: list.call.size,
      missing: list.call(missing: true).size,
      no_translate: list.call(no_translate: true).size,
      archived: list.call(archived: true).size
    }
    @terms = list.call.sort_by { |term| SqliteFold.fold(term.term) }
    @column_stats = column_stats(@all_columns)
  end

  def searched_terms(terms, languages)
    q = params[:q].to_s.strip
    return terms if q.empty?

    folded = SqliteFold.fold(q)
    terms.select do |term|
      entries = languages.filter_map { |language| @matrix.dig(term.id, language.id) }
      [term.term, term.variants, term.definition, *entries.flat_map { |e| [e.term, e.variants, e.avoid, e.note] }]
        .compact.any? { |text| SqliteFold.fold(text).include?(folded) }
    end
  end

  def filter_terms(terms, languages:, archived:, missing:, no_translate:)
    terms.select do |term|
      term.archived? == archived && (!no_translate || term.no_translate) &&
        (!missing || (!term.no_translate && languages.any? { |language| !@matrix.dig(term.id, language.id)&.term }))
    end
  end
end
