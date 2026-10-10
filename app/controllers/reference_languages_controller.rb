# The language shown as the main reference in the translator's editor (fr source or en translation).
# Switched in place by the reference controller (json) : nothing to render.
class ReferenceLanguagesController < ApplicationController
  def update
    current_user.update!(reference_language: params[:reference_language].to_s) if User::REFERENCE_LANGUAGES.include?(params[:reference_language].to_s)
    respond_to do |format|
      format.html { redirect_back_or_to translate_root_path }
      format.json { head :no_content }
    end
  end
end
