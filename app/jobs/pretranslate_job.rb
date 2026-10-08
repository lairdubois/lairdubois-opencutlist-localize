class PretranslateJob < ApplicationJob
  queue_as :default

  def perform(language_id, unit_ids)
    language = Language.find(language_id)
    Pretranslator.new(language).call(Unit.active.where(id: unit_ids).to_a)
  end
end
