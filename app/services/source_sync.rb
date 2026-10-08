# Brings into the database what developers changed in the repo's fr.yml since the last baseline.
# Nothing is applied blindly : the plan lists the changes and the admin decides for each
# rename candidate (rename or delete+add) and each text change (minor or major).
class SourceSync
  Plan = Struct.new(:added, :removed, :changed, :renames, :conflicts, :order, keyword_init: true) do
    def empty?
      added.empty? && removed.empty? && changed.empty?
    end
  end
  # added : [Entry], removed : [Unit], changed : [[Unit, Entry]], renames : [[Unit, Entry]],
  # conflicts : unit ids whose fr text was also changed in the tool

  def initialize(fr_text, author:)
    @fr_text = fr_text
    @entries = I18nYaml::Reader.new(fr_text).entries
    @author = author
  end

  def plan
    baseline = Baseline.current or raise "No baseline : run rake i18n:baseline first"
    base = baseline.by_key
    units = Unit.where(id: baseline.entries.map { |e| e["unit_id"] }.compact).index_by(&:id)
    active_by_key = Unit.active.index_by(&:key)
    repo_keys = @entries.map(&:key).to_set

    added = @entries.reject { |e| base.key?(e.key) }
    removed = base.values.reject { |b| repo_keys.include?(b["key"]) }
                  .filter_map { |b| [units[b["unit_id"]], b["value"]] if units[b["unit_id"]] && !units[b["unit_id"]].archived? }
    changed = @entries.filter_map do |e|
      b = base[e.key]
      unit = b && units[b["unit_id"]]
      [unit, e] if unit && !unit.archived? && b["value"] != e.value && unit.source_text != e.value
    end
    conflicts = changed.filter_map { |unit, e| unit.id if unit.source_text != base[e.key]["value"] }

    renames = match_renames(removed, added)
    # What the repo already agrees with (typically our own merged export) is not a change
    renames.reject! { |unit, e| unit.key == e.key }
    renamed_units = renames.map(&:first)
    renamed_keys = renames.map { |_, e| e.key }
    added.reject! { |e| renamed_keys.exclude?(e.key) && (u = active_by_key[e.key]) && u.source_text == e.value }
    removed = removed.map(&:first).reject { |u| renamed_units.exclude?(u) && repo_keys.include?(u.key) }

    Plan.new(added: added, removed: removed, changed: changed, renames: renames, conflicts: conflicts, order: @entries.map(&:key))
  end

  # decisions : { renames: [unit_id, ...] accepted, majors: [unit_id, ...] text changes that invalidate }
  def apply(plan, decisions = {})
    accepted = Array(decisions[:renames]).map(&:to_i)
    majors = Array(decisions[:majors]).map(&:to_i)
    operations = UnitOperations.new(@author)

    ApplicationRecord.transaction do
      renamed_keys = []
      plan.renames.each do |unit, entry|
        next unless accepted.include?(unit.id)

        operations.rename(unit, entry.key)
        renamed_keys << entry.key
      end
      plan.removed.each { |unit| operations.archive(unit) unless unit.reload.key.in?(renamed_keys) }
      plan.added.each do |entry|
        next if entry.key.in?(renamed_keys) || Unit.active.exists?(key: entry.key)

        operations.create(entry.key, entry.value, note: entry.note)
      end
      plan.changed.each { |unit, entry| operations.edit_source(unit, entry.value, major: majors.include?(unit.id)) }

      # The repo's order is authoritative for the keys it has
      positions = plan.order.each_with_index.to_h
      Unit.active.each { |u| u.update_columns(position: positions[u.key]) if positions[u.key] }

      Baseline.record!(@fr_text, source: "sync")
    end
  end

  private

  # A removed unit and an added entry with the very same fr text are most likely a rename.
  # When a text is shared by several keys, pairs are told apart by the key segments they
  # still have in common (a moved branch keeps its leaf names) ; ambiguous pairs are left out.
  # removed : [[Unit, baseline value]]
  def match_renames(removed, added)
    added_by_text = added.group_by(&:value)
    removed.group_by(&:last).flat_map do |text, pairs_of_text|
      units = pairs_of_text.map(&:first)
      entries = added_by_text[text] || []
      pairs = units.product(entries).map { |u, e| [key_similarity(u.key, e.key), u, e] }.sort_by { |s, _, _| -s }
      used = []
      pairs.filter_map do |score, unit, entry|
        next if used.include?(unit) || used.include?(entry)
        next if pairs.any? { |s, u, e| s == score && (u == unit) != (e == entry) && !used.include?(u) && !used.include?(e) }

        used << unit << entry
        [unit, entry]
      end
    end
  end

  # Common trailing segments weigh more than common leading ones
  def key_similarity(a, b)
    a, b = a.split("."), b.split(".")
    trailing = a.reverse.zip(b.reverse).take_while { |x, y| x == y }.size
    leading = a.zip(b).take_while { |x, y| x == y }.size
    trailing * 100 + leading
  end
end
