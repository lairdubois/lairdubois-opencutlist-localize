class BranchesController < ApplicationController
  before_action :require_admin
  def rename
    prefix, new_prefix = params.require(:prefix), params.require(:new_prefix).strip
    units = UnitOperations.new(current_author).rename_branch(prefix, new_prefix)
    redirect_to units_path(q: new_prefix), notice: t(".moved", count: units.size, from: prefix, to: new_prefix)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to units_path(q: prefix), alert: e.record.errors.full_messages.to_sentence
  end
end
