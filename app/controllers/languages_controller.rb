# Home : the languages the user can work on, with their progress (the @no-translate keys left out)
class LanguagesController < ApplicationController
  def index
    @languages = current_user.editable_languages.to_a
    total = Unit.active.translatable.count
    counts = Translation.joins(:unit).merge(Unit.active.translatable).where(language: @languages).group(:language_id)
                        .pluck(:language_id, Arel.sql("COUNT(*)"),
                               Arel.sql("SUM(translations.source_hash <> units.source_hash)"),
                               Arel.sql("SUM(translations.status = 1)"))
                        .to_h { |id, n, outdated, reviewed| [id, { translated: n, outdated: outdated.to_i, reviewed: reviewed.to_i }] }
    @stats = @languages.to_h { |l| [l, counts.fetch(l.id, { translated: 0, outdated: 0, reviewed: 0 }).merge(total: total)] }
  end
end
