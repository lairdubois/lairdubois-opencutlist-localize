# The admin operations on units, each one recorded as a revision
class UnitOperations
  # author : a User, or a plain name for automated operations (import, sync scripts)
  def initialize(author)
    @user = author if author.is_a?(User)
    @author = @user ? @user.name : author
  end

  def create(key, text, note: nil, position: 0)
    unit = Unit.create!(key: key, source_text: text, note: note, position: position)
    unit.revisions.create!(kind: "create", new_value: text, author: @author, user: @user)
    unit
  end

  def rename(unit, new_key)
    old_key = unit.key
    unit.update!(key: new_key)
    unit.revisions.create!(kind: "rename", old_value: old_key, new_value: new_key, author: @author, user: @user)
    rewrite_references(old_key, new_key, branch: false)
  end

  # Renames a whole branch : every active key under `prefix` moves under `new_prefix`
  def rename_branch(prefix, new_prefix)
    units = Unit.active.where("key = ? OR key LIKE ? ESCAPE '\\'", prefix, "#{Unit.sanitize_sql_like(prefix)}.%").to_a
    old_keys = units.to_h { |u| [u.id, u.key] }
    ApplicationRecord.transaction do
      # Two passes, so that a moved key never collides with another key of the same branch
      units.each { |u| u.update_columns(key: "__moving__.#{u.id}") }
      units.each do |u|
        new_key = new_prefix + old_keys[u.id].delete_prefix(prefix)
        u.update!(key: new_key)
        u.revisions.create!(kind: "rename", old_value: old_keys[u.id], new_value: new_key, author: @author, user: @user)
      end
      rewrite_references(prefix, new_prefix, branch: true)
    end
    units
  end

  # minor : translations stay valid (their source hash follows) ; major : they become outdated
  def edit_source(unit, text, major:)
    old_text = unit.source_text
    old_hash = unit.source_hash
    unit.update!(source_text: text)
    unit.translations.where(source_hash: old_hash).update_all(source_hash: unit.source_hash) unless major
    unit.revisions.create!(kind: major ? "source_major" : "source_minor", old_value: old_text, new_value: text, author: @author, user: @user)
  end

  # Values nest other strings with i18next's $t(key) or $t(key, {options}) : follow the rename.
  # This is not a change of meaning, so translations stay up to date.
  def rewrite_references(old_key, new_key, branch:)
    pattern = /\$t\(#{Regexp.escape(old_key)}(?=#{branch ? "[.,)]" : "[,)]"})/
    replacement = "$t(#{new_key}"
    like = "%$t(#{Unit.sanitize_sql_like(old_key)}%"

    Unit.active.where("source_text LIKE ? ESCAPE '\\'", like).find_each do |unit|
      text = unit.source_text.gsub(pattern, replacement)
      next if text == unit.source_text

      old_hash = unit.source_hash
      unit.update!(source_text: text)
      unit.translations.where(source_hash: old_hash).update_all(source_hash: unit.source_hash)
    end
    Translation.where("text LIKE ? ESCAPE '\\'", like).find_each do |translation|
      text = translation.text.gsub(pattern, replacement)
      translation.update!(text: text) unless text == translation.text
    end
  end

  # The YAML comment written above the key in every language file
  def edit_note(unit, note)
    note = self.class.normalize_note(note)
    old_note = unit.note
    return if note == old_note

    unit.update!(note: note)
    unit.revisions.create!(kind: "note", old_value: old_note, new_value: note, author: @author, user: @user)
  end

  def archive(unit)
    unit.update!(archived_at: Time.current)
    unit.revisions.create!(kind: "archive", old_value: unit.key, author: @author, user: @user)
  end
  # Trailing spaces and leading / trailing blank lines would not survive the YAML round trip
  def self.normalize_note(note)
    lines = note.to_s.gsub("\r\n", "\n").split("\n").map(&:rstrip)
    lines.shift while lines.first == ""
    lines.pop while lines.last == ""
    lines.join("\n").presence
  end
end
