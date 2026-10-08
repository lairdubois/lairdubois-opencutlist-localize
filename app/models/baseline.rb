require "digest"

# The fr.yml of the OCL repo as it was when we last reconciled with it, each key tied to its unit.
# Syncing diffs the repo against this baseline (not against the database), so that what
# the admins changed in the tool and not yet merged in the repo is never seen as a repo change.
class Baseline < ApplicationRecord
  # entries : [{ "key" =>, "value" =>, "note" =>, "unit_id" => }] (no "note" in baselines recorded before notes were synced)

  def self.current
    order(:id).last
  end

  def self.hash_text(text)
    Digest::SHA256.hexdigest(text)
  end

  # A repo key keeps the unit it had in the previous baseline, even when the tool renamed
  # that unit since (the rename is still pending in the repo) ; new repo keys go by current key.
  def self.record!(fr_text, source:)
    previous = current&.by_key || {}
    known = Unit.where(id: previous.values.map { |e| e["unit_id"] }.compact).pluck(:id).to_set # archived = deletion pending in the repo
    units = Unit.active.index_by(&:key)
    entries = I18nYaml::Reader.new(fr_text).entries.map do |e|
      unit_id = previous.dig(e.key, "unit_id")
      unit_id = units[e.key]&.id unless known.include?(unit_id)
      { "key" => e.key, "value" => e.value, "note" => e.note, "unit_id" => unit_id }
    end
    create!(fr_hash: hash_text(fr_text), entries: entries, source: source)
  end

  def by_key
    @by_key ||= entries.index_by { |e| e["key"] }
  end
end
