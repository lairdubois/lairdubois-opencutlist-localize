# Renders every language as <code>.yml, in the repo's key order
class YamlExport
  # { "fr.yml" => "...", ... }
  def files
    units = Unit.active.to_a
    Language.all.to_h do |language|
      entries = if language.source?
                  units.map { |u| I18nYaml::Entry.new(key: u.key, value: u.source_text, note: u.note) }
                else
                  texts = language.translations.where(unit: units).pluck(:unit_id, :text).to_h
                  units.filter_map { |u| I18nYaml::Entry.new(key: u.key, value: texts[u.id], note: u.note) if texts[u.id] }
                end
      ["#{language.code}.yml", I18nYaml::Writer.write(entries)]
    end
  end

  def write(dir)
    files.map { |name, content| File.join(dir, name).tap { |path| File.write(path, content) } }
  end
end
