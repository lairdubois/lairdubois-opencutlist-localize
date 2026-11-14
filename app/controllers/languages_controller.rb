# Home : every target language with its progress (the @no-translate keys left out), in three columns : work left
# (to translate or outdated), to approve, ready. The ones the user can't edit are greyed out, not linked, or left out
# with mine=1 (offered when the user can edit some but not all). Admins manage them (manage) : add one of the ISO
# list (create), delete one with all its work (destroy), say whether it writes compounds (compounding)
class LanguagesController < ApplicationController
  before_action :require_admin, only: [:manage, :create, :destroy, :compounding]

  COLUMNS = { todo: [:outdated, :translating], to_approve: [:translated], ready: [:approved] }.freeze

  def index
    @languages = Language.targets.to_a
    # Linked : the languages the user translates or reads
    @editable = current_user.readable_languages.pluck(:id).to_set
    @mine_filter = @editable.any? && @editable.size < @languages.size
    @mine = @mine_filter && params[:mine] == "1"
    @stats = Language.stats(@languages)
    @states = @languages.to_h { |l| [l, state(@stats[l])] }
    shown = @mine ? @languages.select { |l| @editable.include?(l.id) } : @languages
    @columns = COLUMNS.transform_values { |states| shown.select { |l| states.include?(@states[l]) } }
    # The most advanced first, ties in the usual order : work left on translated (then approved), to approve on approved
    @columns[:todo] = sort_by_progress(@columns[:todo], :translated, :approved)
    @columns[:to_approve] = sort_by_progress(@columns[:to_approve], :approved)
    # Ready : by name, case and accents aside
    @columns[:ready] = @columns[:ready].sort_by { |l| SqliteFold.fold(l.name) }
  end

  def manage
    @languages = Language.targets.to_a
    @translations = Translation.group(:language_id).count
    @members = Membership.group(:language_id).count
    @enabled_languages = enabled_languages
    sort_languages
  end

  # Then on to the users, to give it to translators
  def create
    code = params[:code].to_s
    return redirect_to(manage_languages_path, alert: t(".invalid")) unless Language.new_codes.include?(code)

    language = Language.create_from_iso!(code)
    redirect_to users_path, notice: t(".created", language: language.name)
  end

  # Its yml stays in the OCL repo : publishing writes the existing languages' files only
  def destroy
    language = Language.find(params[:id])
    back = manage_languages_path(sort: params[:sort], dir: params[:dir])
    return redirect_to(back, alert: t(".protected", code: language.code.upcase)) unless language.deletable?

    language.destroy!
    redirect_to back, notice: t(".destroyed", language: language.name)
  end

  # Writes compounds or not : the glossary's expected term may then be inside a longer word (Glossary#warnings).
  # Answers with its button alone (scroll kept)
  def compounding
    language = Language.targets.find(params[:id])
    language.update!(compounding: params[:enabled] == "1")
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(language, :compounding), partial: "compounding_button",
                                                  locals: { language: language, sort: params[:sort], dir: params[:dir] })
      end
      format.html { redirect_to manage_languages_path(sort: params[:sort], dir: params[:dir]) }
    end
  end

  private

  # OCL's ENABLED_LANGUAGES as a %w[] literal : the fr source and the targets translated at 100 % (outdated included, as
  # the progress bars), sorted by code
  def enabled_languages
    complete = Language.stats(@languages).select { |_, s| s[:total].positive? && s[:translated] >= s[:total] }.keys.map(&:code)
    "%w[#{(complete + [Language::SOURCE_CODE]).sort.join(" ")}]"
  end

  # manage's columns, sortable through `sort` : counts start descending, the language (its code) ascending
  MANAGE_SORTS = %w[language translations members].freeze

  def sort_languages
    @sort = MANAGE_SORTS.include?(params[:sort]) ? params[:sort] : "language"
    @dir = %w[asc desc].include?(params[:dir]) ? params[:dir] : default_dir(@sort)
    sign = @dir == "desc" ? -1 : 1
    # Ties stay by code, whatever the direction
    @languages = @languages.sort { |a, b| (sign * (sort_value(a) <=> sort_value(b))).nonzero? || a.code <=> b.code }
  end

  def default_dir(sort) = sort == "language" ? "asc" : "desc"
  helper_method :default_dir

  def sort_value(language)
    case @sort
    when "language" then language.code
    when "translations" then @translations.fetch(language.id, 0)
    when "members" then @members.fetch(language.id, 0)
    end
  end

  def sort_by_progress(languages, *counts)
    languages.each_with_index.sort_by { |l, i| [*counts.map { |c| -@stats[l][c] }, i] }.map(&:first)
  end

  def state(s)
    if s[:outdated] > 0 then :outdated
    elsif s[:translated] < s[:total] then :translating
    elsif s[:approved] < s[:total] then :translated
    else :approved
    end
  end
end
