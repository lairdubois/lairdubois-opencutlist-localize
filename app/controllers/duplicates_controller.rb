# A language's fr texts repeated over several keys and translated in several ways, for its translators to harmonize.
# The translators' work only (SourceDuplicates translatable)
class DuplicatesController < ApplicationController
  before_action :set_language

  def index
    @groups = SourceDuplicates.new(@language, translatable: true).divergent
    # Each group's "edit" button opens its keys in the language's translator's list (?at=index,index,…)
    @indexes = Unit.tree_indexes(@groups.flat_map { |g| g.units.map(&:id) })
  end

  private

  def set_language
    @language = Language.targets.find_by!(code: params[:lang])
    redirect_to translate_root_path, alert: t("flash.no_language_access") unless current_user.can_read?(@language)
  end
end
