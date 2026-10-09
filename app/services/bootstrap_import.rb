# First import of an i18n-src directory (fr.yml + the translated files) into an empty database
class BootstrapImport
  Result = Struct.new(:languages, :units, :translations, :orphans, keyword_init: true)

  def initialize(dir, author: "import")
    @dir = dir
    @author = author
  end

  def call
    raise "Database is not empty" if Unit.exists?

    result = Result.new(languages: 0, units: 0, translations: 0, orphans: Hash.new(0))
    ApplicationRecord.transaction do
      files = Dir[File.join(@dir, "*.yml")].sort_by { |p| [File.basename(p, ".yml") == Language::SOURCE_CODE ? 0 : 1, p] }
      units = {}
      files.each_with_index do |path, index|
        code = File.basename(path, ".yml")
        entries = I18nYaml::Reader.read_file(path)
        label = entries.find { |e| e.key == "_label" }&.value
        language = Language.create!(code: code, name: label || code, rtl: %w[ar he].include?(code), position: index)
        result.languages += 1

        if language.source?
          entries.each_with_index do |entry, position|
            unit = Unit.create!(key: entry.key, source_text: entry.value, note: entry.note, position: position)
            unit.revisions.create!(kind: "import", new_value: entry.value, author: @author)
            units[entry.key] = unit
          end
          result.units = units.size
        else
          entries.each do |entry|
            unit = units[entry.key]
            next result.orphans[code] += 1 unless unit
            next if entry.value.empty? # Transifex exports untranslated strings as "", gulp falls back to en for both

            unit.translations.create!(language: language, text: entry.value, source_hash: unit.source_hash)
            result.translations += 1
          end
        end
      end
      fr_text = File.read(File.join(@dir, "#{Language::SOURCE_CODE}.yml"))
      operations = UnitOperations.new(@author)
      I18nYaml::Reader.new(fr_text).branch_notes.each { |path, note| operations.edit_branch_note(path, note) }
      Unit.refresh_translatable!
      Baseline.record!(fr_text, source: "bootstrap")
    end
    result
  end
end
