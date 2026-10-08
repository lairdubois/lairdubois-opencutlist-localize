module I18nYaml
  # One translatable string of a YAML file : dotted key, raw value, leading comment
  Entry = Struct.new(:key, :value, :note, keyword_init: true)
end
