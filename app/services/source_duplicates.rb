# Groups of active units sharing the same fr text : candidates for a single key the others point to with
# $t(). A text that is a $t() alone is already one. Each unit comes with its translation in a language,
# to spot the groups translated in different ways (the Python lint's compare_repetitions).
class SourceDuplicates
  REFERENCE_ONLY = /\A\$t\([^)]*\)\z/

  Group = Data.define(:text, :units, :translations) do
    # Translated in more than one way (untranslated units aside)
    def divergent?
      translations.values.compact.uniq.size > 1
    end

    # The most common translation, the others being the divergent ones
    def usual_translation
      translations.values.compact.tally.max_by(&:last)&.first
    end
  end

  attr_reader :groups

  def initialize(language)
    units = Unit.active.reorder(:position, :id).to_a
    by_text = units.group_by(&:source_text).select { |text, same| same.size > 1 && !text.to_s.strip.match?(REFERENCE_ONLY) }
    texts = Translation.where(language: language, unit_id: by_text.values.flatten.map(&:id)).pluck(:unit_id, :text).to_h
    # Largest groups first, then in tree order
    @groups = by_text.map { |text, same| Group.new(text:, units: same, translations: same.to_h { |u| [u.id, texts[u.id]] }) }
                     .sort_by { |g| -g.units.size }
  end

  def divergent
    groups.select(&:divergent?)
  end
end
