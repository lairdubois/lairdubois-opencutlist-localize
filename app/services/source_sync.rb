# Brings into the database what developers changed in the repo's fr.yml since the last baseline.
# Nothing is applied blindly : the plan lists the changes and the admin decides for each
# rename candidate (rename or delete+add) and each text change (minor or major).
class SourceSync
  Plan = Struct.new(:added, :removed, :changed, :renames, :conflicts, :notes, :note_conflicts, :branch_notes, :order, keyword_init: true) do
    def empty?
      added.empty? && removed.empty? && changed.empty? && notes.empty? && branch_notes.empty?
    end
  end
  # added : [Entry], removed : [Unit], changed : [[Unit, Entry]], renames : [[Unit, Entry]],
  # conflicts : unit ids whose fr text was also changed in the tool,
  # notes : [[Unit, Entry]] YAML comment changed in the repo, note_conflicts : unit ids whose comment was also changed in the tool,
  # branch_notes : [BranchChange] comments above branches changed in the repo
  BranchChange = Struct.new(:path, :note, :tool_note, :conflict, keyword_init: true)

  def initialize(fr_text, author:)
    @fr_text = fr_text
    reader = I18nYaml::Reader.new(fr_text)
    @entries = reader.entries
    @branch_notes = reader.branch_notes
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

    notes = note_changes(baseline, units, renames)
    note_conflicts = notes.filter_map { |unit, _| unit.id if note(unit.note) != base_note(baseline, unit) }

    Plan.new(added: added, removed: removed, changed: changed, renames: renames, conflicts: conflicts,
             notes: notes, note_conflicts: note_conflicts, branch_notes: branch_note_changes(baseline), order: @entries.map(&:key))
  end

  # decisions : { renames: [unit_id, ...] accepted, majors: [unit_id, ...] text changes that invalidate,
  #               notes: [unit_id, ...] repo comments taken (the others keep the tool's one, written on publish),
  #               branch_notes: [path, ...] same for the branches' comments }
  def apply(plan, decisions = {})
    accepted = Array(decisions[:renames]).map(&:to_i)
    majors = Array(decisions[:majors]).map(&:to_i)
    taken_notes = Array(decisions[:notes]).map(&:to_i)
    taken_branch_notes = Array(decisions[:branch_notes]).map(&:to_s)
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
      plan.notes.each do |unit, entry|
        operations.edit_note(unit, entry.note) if taken_notes.include?(unit.id) && !unit.reload.archived?
      end
      plan.branch_notes.each { |change| operations.edit_branch_note(change.path, change.note) if taken_branch_notes.include?(change.path) }

      # The repo's order is authoritative for the keys it has
      positions = plan.order.each_with_index.to_h
      Unit.active.each { |u| u.update_columns(position: positions[u.key]) if positions[u.key] }

      Baseline.record!(@fr_text, source: "sync")
    end
  end

  private

  # Units whose comment differs between the repo and the baseline (and not already the same in the tool).
  # Renamed keys are compared through their unit ; a rename left unchecked creates a new unit with the repo's comment anyway.
  def note_changes(baseline, units, renames)
    pairs = @entries.filter_map do |e|
      b = baseline.by_key[e.key]
      unit = b && units[b["unit_id"]]
      [unit, e] if unit && !unit.archived?
    end
    (pairs + renames).uniq { |unit, _| unit.id }.select do |unit, e|
      repo = note(e.note)
      repo != base_note(baseline, unit) && repo != note(unit.note)
    end
  end

  # Branch comments that differ between the repo and the baseline (and not already the same in the tool).
  # A branch moved in the repo shows as its comment removed from the old path and added on the new one.
  def branch_note_changes(baseline)
    tool = BranchNote.to_map
    # Baselines recorded before branch notes were synced have none : the tool had none either then
    base = baseline.branch_notes || {}
    (@branch_notes.keys | base.keys).filter_map do |path|
      repo, before, current = note(@branch_notes[path]), note(base[path]), note(tool[path])
      BranchChange.new(path: path, note: repo, tool_note: current, conflict: current != before) if repo != before && repo != current
    end
  end

  # Baselines recorded before notes were synced have none : the tool's comment stands in for it
  def base_note(baseline, unit)
    @base_by_unit ||= baseline.entries.index_by { |e| e["unit_id"] }
    b = @base_by_unit[unit.id]
    b&.key?("note") ? note(b["note"]) : note(unit.note)
  end

  def note(text)
    UnitOperations.normalize_note(text)
  end

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
