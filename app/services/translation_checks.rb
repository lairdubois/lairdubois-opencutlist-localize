# Warnings about a translation compared to its fr source. They never block saving.
class TranslationChecks
  TOKENS = {
    variable: /\{\{\s*[\w.]+\s*\}\}/,         # {{ count }}
    reference: /\$t\([^)]*\)/,                 # $t(tab.cutlist.label)
    tag: %r{</?[a-z][^>]*>}i,                   # <br>, <strong>
  }.freeze

  def self.call(source, text)
    new(source, text).warnings
  end

  def initialize(source, text)
    @source = source.to_s
    @text = text.to_s
  end

  def warnings
    return [] if @text.empty?

    out = []
    TOKENS.each do |kind, pattern|
      expected = @source.scan(pattern).map { |t| t.gsub(/\s+/, "") }.tally
      found = @text.scan(pattern).map { |t| t.gsub(/\s+/, "") }.tally
      (expected.keys | found.keys).each do |token|
        if expected[token].to_i > found[token].to_i then out << I18n.t("translation_checks.missing.#{kind}", token: token)
        elsif found[token].to_i > expected[token].to_i then out << I18n.t("translation_checks.extra.#{kind}", token: token)
        end
      end
    end
    out << I18n.t("translation_checks.bold") if @source.scan("**").size != @text.scan("**").size
    out << I18n.t("translation_checks.lines") if @source.count("\n") != @text.count("\n")
    out << I18n.t("translation_checks.spaces") if @text != @text.strip && @source == @source.strip
    out
  end
end
