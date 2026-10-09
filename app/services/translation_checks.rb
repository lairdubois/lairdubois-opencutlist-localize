# Warnings about a text, never blocking a save. Text rules look at a text alone (any language, the fr
# source included) ; a translation also gets compared with its fr source (invariants, markdown markers,
# lines, final dot, quotes).
class TranslationChecks
  TOKENS = {
    variable: /\{\{\s*[\w.]+\s*\}\}/,         # {{ count }}
    reference: /\$t\([^)]*\)/,                 # $t(tab.cutlist.label)
    tag: %r{</?[a-z][^>]*>}i,                   # <br>, <strong>
  }.freeze

  TEXT_RULES = {
    double_space: /(?<=\S)[ \t]{2,}(?=\S)/,     # inside a line, indentation aside
    line_end_space: /[ \t]\n/,                  # the text's own ends are a comparison rule
    space_before_comma: /[ \t],/,
    link_space: /\][ \t]+\(/,                   # [label] (url) : no longer a markdown link
    insecure_url: %r{http://},
    url_space: %r{https?://\s},
    loose_bold: /\s\*\*\s/,                     # ** bold ** isn't bold
    triple_star: /\*{3,}/,
    invisible: /[\u200B\u2060\uFEFF\u00AD]/,    # zero width space, word joiner, BOM, soft hyphen
  }.freeze

  # 'Name' : a quoted identifier (attribute, css class) the code relies on. The lookarounds skip
  # elisions (l'attribut)
  LITERAL = /(?<![[:alpha:]])'[A-Za-z][\w.-]*'(?![[:alpha:]])/
  TYPOGRAPHIC_QUOTES = /[«»„“”]/

  RULES_DIGEST = Digest::MD5.hexdigest(File.read(__FILE__))

  # A translation : its comparison with the source, then the text rules the source doesn't break itself
  # (the translator isn't asked to fix those : they show on the key page)
  def self.call(source, text)
    return [] if text.to_s.empty?

    comparison_warnings(source.to_s, text.to_s) + messages(text_rules(text.to_s) - text_rules(source.to_s))
  end

  # A text alone, e.g. the fr source
  def self.text(text)
    messages(text_rules(text.to_s))
  end

  # Set of the active units with a warning : in a language's translations, or (no language) in any
  # translation or in the fr source. For the search's "warnings" filter. Cached until a text changes
  # (no bulk write touches a text without its updated_at) or these rules do.
  def self.unit_ids(language = nil)
    units = Unit.active.reorder(nil)
    translations = Translation.joins(:unit).merge(units)
    translations = translations.where(language: language) if language
    fingerprint = [units, translations].map { |scope| scope.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(#{scope.table_name}.updated_at)")) }
    Rails.cache.fetch(["translation_checks", RULES_DIGEST, language&.id, fingerprint]) do
      ids = translations.pluck(:unit_id, "units.source_text", :text).filter_map { |id, source, text| id if call(source, text).any? }
      ids += units.pluck(:id, :source_text).filter_map { |id, source| id if text_rules(source.to_s).any? } unless language
      ids.to_set
    end
  end

  def self.text_rules(text)
    TEXT_RULES.filter_map { |rule, pattern| rule if text.match?(pattern) }
  end

  def self.messages(rules)
    rules.map { |rule| I18n.t("translation_checks.text.#{rule}") }
  end

  def self.comparison_warnings(source, text)
    out = []
    TOKENS.each do |kind, pattern|
      expected = source.scan(pattern).map { |t| t.gsub(/\s+/, "") }.tally
      found = text.scan(pattern).map { |t| t.gsub(/\s+/, "") }.tally
      (expected.keys | found.keys).each do |token|
        if expected[token].to_i > found[token].to_i then out << I18n.t("translation_checks.missing.#{kind}", token: token)
        elsif found[token].to_i > expected[token].to_i then out << I18n.t("translation_checks.extra.#{kind}", token: token)
        end
      end
    end
    (source.scan(LITERAL).uniq - text.scan(LITERAL)).each { |literal| out << I18n.t("translation_checks.literal", token: literal) }
    out << I18n.t("translation_checks.bold") if source.scan("**").size != text.scan("**").size
    out << I18n.t("translation_checks.italic") if italics(source) != italics(text)
    out << I18n.t("translation_checks.lines") if source.count("\n") != text.count("\n")
    out << I18n.t("translation_checks.spaces") if text != text.strip && source == source.strip
    # Sentences only (the source's words : Chinese has no spaces) : labels and abbreviations ("Surf.") vary
    dots = [final_dot(source), final_dot(text)]
    if source.split.size >= 3 && dots.none?(nil) && dots.uniq.size == 2
      out << I18n.t(dots.first ? "translation_checks.final_dot.missing" : "translation_checks.final_dot.extra")
    end
    out << I18n.t("translation_checks.typographic_quotes") if text.match?(TYPOGRAPHIC_QUOTES) && !source.match?(TYPOGRAPHIC_QUOTES)
    out
  end

  # Single * (italic), the ** of bold aside
  def self.italics(text)
    text.gsub("**", "").count("*")
  end

  # Whether a text ends with a dot (。 in Chinese), markdown markers aside ; nil for an ellipsis
  def self.final_dot(text)
    ending = text.strip.sub(/\*+\z/, "")
    ending.end_with?(".", "。") unless ending.end_with?("…", "...")
  end
  private_class_method :text_rules, :messages, :comparison_warnings, :italics, :final_dot
end
