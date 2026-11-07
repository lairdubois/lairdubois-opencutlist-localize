# The glossary's lookups for some languages : the terms of a fr text, each language's entries, the warnings of a
# translation (TranslationChecks) and what the pre-translation is told. Loaded in two queries, the fr texts' terms
# memoized per text. The terms of a text in one of these languages are found through its entries' forms (`via` : the
# translator's en reference), the ones kept as is through their fr forms.
# Matching : whole words (not at the edges written in a script without spaces), case and accents aside
# (SqliteFold.fold), any whitespace inside a form, the invariants ({{ var }}, $t(), tags, entities) left out. On
# overlap, the longest term wins (« plan de coupe » over « plan »). Same rules in lib/i18n_text.js. In a language
# writing compounds (COMPOUNDING), the expected term may also be inside a longer word (« Platte » in « Plattenrest », « Teile » in « Gruppenteile »).
class Glossary
  INVARIANTS = Regexp.union(*TranslationChecks::TOKENS.values, /&(?:[a-zA-Z]+|#\d+);/)
  # A form edged by one of these characters needs no word boundary on that side
  UNSPACED = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}\p{Lao}\p{Khmer}\p{Myanmar}]/
  BEFORE = "(?<![\\p{L}\\p{N}_])".freeze
  AFTER = "(?![\\p{L}\\p{N}_])".freeze
  # Languages whose compounds may start or end with the expected term : no word boundary needed
  COMPOUNDING = %w[de nl].freeze

  attr_reader :terms

  # Changes whenever a term or an entry does (TranslationChecks.unit_ids' cache)
  def self.fingerprint
    [GlossaryTerm, GlossaryEntry].map { |model| model.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)")) }
  end

  # A text as matched : invariants blanked, folded
  def self.prepare(text)
    SqliteFold.fold(text.to_s.gsub(INVARIANTS, " "))
  end

  # A regexp of some forms, on prepared texts. prefix : a form may be part of a longer word
  def self.pattern(forms, prefix: false)
    Regexp.union(forms.filter_map do |form|
      words = SqliteFold.fold(form).split
      next if words.empty?

      body = words.map { |w| Regexp.escape(w) }.join("[[:space:]]+")
      Regexp.new("#{BEFORE unless prefix || words.first.match?(/\A#{UNSPACED}/)}#{body}#{AFTER unless prefix || words.last.match?(/#{UNSPACED}\z/)}")
    end)
  end

  def initialize(languages = Language.targets)
    @terms = GlossaryTerm.active.order(:term).to_a
    @entries = GlossaryEntry.where(glossary_term_id: @terms.map(&:id), language: languages).index_by { |e| [e.glossary_term_id, e.language_id] }
    @patterns = @terms.to_h { |term| [term, self.class.pattern(term.forms)] }
    @lookups = {}
    @found = {}
  end

  def entry(term, language)
    @entries[[term.id, language.id]]
  end

  # The terms of a fr text, in order of appearance ; via : of a text in that language (one of the loaded ones)
  def terms_in(source, via: nil)
    @found[[via&.id, source]] ||= find_terms(self.class.prepare(source), via)
  end

  # The forms of a term looked for in a text of via's language (fr : none given) : none without its entry there
  def forms_for(term, via = nil)
    via.nil? || term.no_translate ? term.forms : entry(term, via)&.forms || []
  end

  # The glossary's warnings on a translation : a term kept as is (no_translate) translated, the expected term
  # missing, a term to avoid used
  def warnings(source, text, language)
    found = terms_in(source)
    return [] if found.empty? || text.to_s.empty?

    prepared = self.class.prepare(text)
    found.flat_map do |term|
      if term.no_translate
        prepared.match?(@patterns[term]) ? [] : [I18n.t("translation_checks.glossary.keep", term: term.term)]
      elsif (entry = entry(term, language))
        out = []
        if entry.term && !prepared.match?(self.class.pattern(entry.forms, prefix: COMPOUNDING.include?(language.code)))
          out << I18n.t("translation_checks.glossary.expected", term: term.term, expected: entry.term)
        end
        entry.avoided.each do |avoided|
          out << I18n.t("translation_checks.glossary.avoid", avoid: avoided, term: term.term) if prepared.match?(self.class.pattern([avoided]))
        end
        out
      else
        []
      end
    end
  end

  # A term and its entry in a language, as the pre-translation and the API give them
  def describe(term, language)
    entry = entry(term, language)
    {
      fr: term.term,
      fr_variants: GlossaryTerm.split_list(term.variants).presence,
      definition: term.definition,
      keep_as_is: (true if term.no_translate),
      translation: entry&.term,
      variants: GlossaryTerm.split_list(entry&.variants).presence,
      avoid: entry&.avoided.presence,
      note: entry&.note
    }.compact
  end

  # The terms of some fr texts, described for a language
  def describe_in(sources, language)
    sources.flat_map { |source| terms_in(source) }.uniq.map { |term| describe(term, language) }
  end

  private

  # The terms' patterns in via's language, and a quick test before trying each term : any form's first word
  def lookup(via)
    @lookups[via&.id] ||= begin
      forms = @terms.to_h { |term| [term, forms_for(term, via)] }.reject { |_, list| list.empty? }
      patterns = via ? forms.to_h { |term, list| [term, self.class.pattern(list)] } : @patterns
      [patterns, Regexp.union(forms.values.flatten.filter_map { |f| SqliteFold.fold(f).split.first }.uniq)]
    end
  end

  def find_terms(text, via)
    patterns, any = lookup(via)
    return [] if patterns.empty? || !text.match?(any)

    hits = patterns.flat_map { |term, pattern| text.to_enum(:scan, pattern).map { [term, $~.begin(0), $~.end(0)] } }
    # Several terms on the same words (two fr terms sharing an en one) are all kept
    kept = []
    hits.sort_by { |_, from, to| [from - to, from] }.each do |hit|
      kept << hit if kept.none? { |_, from, to| hit[1] < to && hit[2] > from && [from, to] != hit[1, 2] }
    end
    kept.sort_by { |_, from| from }.map(&:first).uniq
  end
end
