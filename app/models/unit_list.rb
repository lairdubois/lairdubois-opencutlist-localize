# The keys list : the active units in tree order, narrowed by a ListFilters::Query. Shown by
# UnitsController#index, and walked by a key page's previous / next.
class UnitList
  attr_reader :query, :units, :indexes, :stats

  def initialize(query, languages:)
    @query = query
    @languages = languages
    @units = Unit.active.reorder(:position, :id).to_a
    # 1-based index of each key in the flattened tree, same as on the translator's page
    @indexes = @units.each.with_index(1).to_h { |unit, i| [unit.id, i] }
    @stats = self.class.stats
  end

  # Per unit id : [translations count, outdated count, up to date not reviewed count, up to date reviewed count]
  def self.stats
    up_to_date = "translations.source_hash = units.source_hash"
    Translation.joins(:unit).merge(Unit.active).group(:unit_id)
               .pluck(:unit_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(translations.source_hash <> units.source_hash)"),
                      Arel.sql("SUM(translations.status = #{Translation.statuses[:translated].to_i} AND #{up_to_date})"),
                      Arel.sql("SUM(translations.status = #{Translation.statuses[:reviewed].to_i} AND #{up_to_date})"))
               .to_h { |id, n, outdated, unreviewed, reviewed| [id, [n, outdated.to_i, unreviewed.to_i, reviewed.to_i]] }
  end

  # Paths of the branches whose keys are all @no-translate, among every key (not only the listed ones)
  def notranslate_branches
    @notranslate_branches ||= begin
      translated = Set.new
      all = Set.new
      units.each do |unit|
        parts = unit.key.split(".")
        paths = (1...parts.size).map { |n| parts.first(n).join(".") }
        all.merge(paths)
        translated.merge(paths) if unit.translatable
      end
      all - translated
    end
  end

  # Units matching the search text and fields (key, branch, user, index range but a single index),
  # whatever the filters
  def searched
    @searched ||= begin
      units = @units
      if (key = query[:key]&.downcase)
        units = units.select { |u| u.key.downcase.include?(key) }
      end
      if (prefix = query[:prefix])
        units = units.select { |u| u.key == prefix || u.key.start_with?("#{prefix}.") }
      end
      if query[:user]
        ids = query.user ? Revision.unscope(:order).by_user(query.user).distinct.pluck(:unit_id).to_set : Set.new
        units = units.select { |u| ids.include?(u.id) }
      end
      if (q = query[:q])
        q = SqliteFold.fold(q)
        units = units.select { |u| SqliteFold.fold(u.source_text).include?(q) }
      end
      query.single_index? ? units : filter_by_index(units)
    end
  end

  # The listed units
  def listed
    @listed ||= (query.single_index? ? filter_by_index(searched) : searched).select { |u| match?(u) }
  end

  # Each status's matches with the other filters (shown in the filters menu), the questions', warnings',
  # notranslate's and periods' ones, and the search alone (for the empty list hint). A single index drops the other
  # filters when applied (ListFilters) and they drop it : the counts leave it out.
  def counts
    ListFilters::STATUSES.to_h { |key| [key, searched.count { |u| status?(key, u) && questions_match?(u) && warnings_match?(u) && notranslate_match?(u) && days_match?(u) }] }
                         .merge("questions" => searched.count { |u| status_match?(u) && question_ids.include?(u.id) && warnings_match?(u) && notranslate_match?(u) && days_match?(u) },
                                "warnings" => searched.count { |u| status_match?(u) && questions_match?(u) && warning_ids.include?(u.id) && notranslate_match?(u) && days_match?(u) },
                                "notranslate" => searched.count { |u| status_match?(u) && questions_match?(u) && warnings_match?(u) && !u.translatable && days_match?(u) })
                         .merge(ListFilters::PERIODS.to_h { |days| ["days_#{days}", searched.count { |u| status_match?(u) && questions_match?(u) && warnings_match?(u) && notranslate_match?(u) && revised_ids(days.to_i).include?(u.id) }] })
                         .merge(searched: searched.size)
  end

  # Listed units around a unit of the tree (listed or not) : [previous, next]
  def neighbours(unit)
    index = indexes.fetch(unit.id)
    [listed.reverse_each.find { |u| indexes[u.id] < index }, listed.find { |u| indexes[u.id] > index }]
  end

  private

  def match?(unit)
    status_match?(unit) && questions_match?(unit) && warnings_match?(unit) && notranslate_match?(unit) && days_match?(unit)
  end

  def notranslate_match?(unit)
    !query.notranslate? || !unit.translatable
  end

  def days_match?(unit)
    !query.days || revised_ids(query.days).include?(unit.id)
  end

  def questions_match?(unit)
    !query.questions? || question_ids.include?(unit.id)
  end

  def warnings_match?(unit)
    !query.warnings? || warning_ids.include?(unit.id)
  end

  # Statuses apply across every target language : "untranslated" = missing in at least one of them,
  # but "reviewed" = reviewed and up to date in all of them
  def status?(key, unit)
    translated, outdated, unreviewed, reviewed = stats.fetch(unit.id, [0, 0, 0, 0])
    case key
    when "untranslated" then translated < @languages
    when "outdated" then outdated > 0
    when "unreviewed" then unreviewed > 0
    when "reviewed" then reviewed == @languages
    end
  end

  # Checked statuses, OR-ed (none = every unit)
  def status_match?(unit)
    query.statuses.empty? || query.statuses.any? { |key| status?(key, unit) }
  end

  def filter_by_index(units)
    return units if query[:at].blank?

    from, to = query.index_range
    units.select { |u| (i = indexes[u.id]) >= (from || 1) && (to.nil? || i <= to) }
  end

  def question_ids
    @question_ids ||= Comment.open_questions.distinct.pluck(:unit_id).to_set
  end

  # Changed in the last days : any revision (in any language, of the fr source, of the key or its note)
  def revised_ids(days)
    (@revised_ids ||= {})[days] ||= Revision.unscope(:order).where(created_at: days.days.ago..).distinct.pluck(:unit_id).to_set
  end

  # In any target language or in the fr source
  def warning_ids
    @warning_ids ||= TranslationChecks.unit_ids
  end
end
