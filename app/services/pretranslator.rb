require "anthropic"

# Proposes translations with Claude. Results are stored as suggestions, never as translations :
# a translator accepts or corrects each one.
class Pretranslator
  MODEL = :"claude-opus-5-5"
  BATCH_SIZE = 25

  SCHEMA = {
    type: "object",
    properties: {
      translations: {
        type: "array",
        items: {
          type: "object",
          properties: { id: { type: "integer" }, text: { type: "string" } },
          required: %w[id text],
          additionalProperties: false
        }
      }
    },
    required: ["translations"],
    additionalProperties: false
  }.freeze

  SYSTEM = <<~PROMPT.freeze
    You translate the user interface of OpenCutList, a SketchUp extension for woodworkers
    (cutting lists, cutting diagrams, panel nesting, labels, cost and weight reports, cabinet building tools).
    The source language is French ; an English version is given as a reference when it exists.

    Rules :
    - Keep every {{ variable }}, $t(key) reference, HTML tag and markdown marker (**bold**, *italic*, [text](url)) exactly as in the source.
    - Keep line breaks : the translation has the same number of lines as the source.
    - Use the woodworking vocabulary a craftsman of the target language would use, and stay consistent with the existing translations given as examples.
    - Short UI labels stay short.
    Answer with one translation per requested id.
  PROMPT

  def self.enabled?
    ENV["ANTHROPIC_API_KEY"].present?
  end

  def initialize(language, client: Anthropic::Client.new)
    @language = language
    @client = client
  end

  # Creates or replaces a suggestion for each unit ; returns the number of suggestions written
  def call(units)
    units.each_slice(BATCH_SIZE).sum { |batch| translate_batch(batch) }
  end

  private

  def translate_batch(units)
    message = @client.beta.messages.create(
      model: MODEL,
      max_tokens: 16_000,
      system_: [{ type: "text", text: SYSTEM }],
      messages: [{ role: "user", content: prompt(units) }],
      output_config: { format_: { type: :json_schema, schema: SCHEMA } },
      fallbacks: :default,
      betas: ["server-side-fallback-2026-07-01"]
    )
    return 0 if message.stop_reason == :refusal

    text = message.content.select { |b| b.type == :text }.map(&:text).join
    by_id = units.index_by(&:id)
    JSON.parse(text).fetch("translations").count do |t|
      unit = by_id[t["id"]]
      next false unless unit && t["text"].present?

      Suggestion.where(unit: unit, language: @language).delete_all
      Suggestion.create!(unit: unit, language: @language, text: t["text"], origin: MODEL.to_s)
    end
  end

  def prompt(units)
    en = Language.find_by(code: "en")
    references = en ? Translation.where(unit: units, language: en).pluck(:unit_id, :text).to_h : {}
    strings = units.map { |u| { id: u.id, key: u.key, fr: u.source_text, en: references[u.id], note: u.note }.compact }

    <<~PROMPT
      Target language : #{@language.name} (#{@language.code})

      Existing reviewed translations, as examples of the expected vocabulary and tone :
      #{examples(units).to_json}

      Strings to translate :
      #{strings.to_json}
    PROMPT
  end

  # Reviewed (else any) translations of this language from the same branches, short ones first
  def examples(units)
    branches = units.map { |u| u.key.split(".").first(2).join(".") }.uniq
    scope = Translation.joins(:unit).merge(Unit.active).where(language: @language).where.not(unit_id: units.map(&:id))
    scope = scope.where(branches.map { "units.key LIKE ?" }.join(" OR "), *branches.map { |b| "#{Unit.sanitize_sql_like(b)}.%" })
    scope.reorder("translations.status DESC", Arel.sql("LENGTH(units.source_text)")).limit(40)
         .pluck("units.source_text", "translations.text").map { |fr, t| { fr: fr, translation: t } }
  end
end
