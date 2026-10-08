# Last pull from Transifex before switching : latest texts, reviewed statuses and translator names.
# analyze is read-only ; apply writes what analyze found.
class TransifexImport
  # Per language :
  #   found : Transifex translations with a text, matched : tied to a unit,
  #   updates : [[unit, text, username, reviewed]] text newer in Transifex,
  #   reviews : [unit] reviewed in Transifex, not here,
  #   conflicts : [[unit, text, username]] text differs but was edited in the tool since the import (ours kept),
  #   unmatched : Transifex keys with no unit
  Report = Struct.new(:language, :found, :matched, :updates, :reviews, :conflicts, :unmatched, :translators, keyword_init: true)

  def initialize(client = TransifexClient.new)
    @client = client
  end

  PARALLEL_FETCHES = 6

  def analyze
    languages = Language.targets.to_a
    queue = Queue.new
    languages.each { |l| queue << l }
    fetched = {}
    errors = []
    Array.new(PARALLEL_FETCHES) do
      Thread.new do
        while (language = (queue.pop(true) rescue nil))
          begin
            fetched[language.code] = fetch(language)
          rescue StandardError => e
            errors << e
          end
        end
      end
    end.each(&:join)
    raise errors.first if errors.any?

    languages.map { |language| analyze_language(language, *fetched.fetch(language.code)) }
  end

  def apply(reports)
    ApplicationRecord.transaction do
      reports.each do |r|
        r.updates.each do |unit, text, username, reviewed|
          translation = unit.translations.find_or_initialize_by(language: r.language)
          old = translation.text
          translation.update!(text: text, source_hash: unit.source_hash, status: reviewed ? :reviewed : :translated)
          unit.revisions.create!(kind: "import", language: r.language, old_value: old, new_value: text, author: "transifex:#{username || '?'}")
        end
        r.reviews.each do |unit|
          translation = unit.translations.find_by(language: r.language) or next
          translation.update!(status: :reviewed)
          unit.revisions.create!(kind: "review", language: r.language, new_value: translation.text, author: "transifex")
        end
      end
    end
  end

  private

  def fetch(language)
    @client.list("/resource_translations",
                 "filter[resource]" => @client.resource_id, "filter[language]" => @client.language_id(language.code),
                 "include" => "resource_string", "limit" => 1000)
  end

  def analyze_language(language, data, included)
    keys = included.select { |i| i["type"] == "resource_strings" }.to_h { |i| [i["id"], normalize_key(i.dig("attributes", "key"))] }
    units = units_by_repo_key
    ours = language.translations.index_by(&:unit_id)
    edited_here = Revision.where(language: language, kind: %w[translate review]).where.not(user_id: nil).distinct.pluck(:unit_id).to_set

    report = Report.new(language: language, found: 0, matched: 0, updates: [], reviews: [], conflicts: [], unmatched: [], translators: Hash.new(0))
    data.each do |t|
      text = t.dig("attributes", "strings", "other")
      next if text.blank?

      report.found += 1
      key = keys[t.dig("relationships", "resource_string", "data", "id")]
      unit = units[key]
      next report.unmatched << key unless unit

      report.matched += 1
      username = t.dig("relationships", "translator", "data", "id")&.delete_prefix("u:")
      report.translators[username] += 1 if username
      mine = ours[unit.id]
      reviewed = t.dig("attributes", "reviewed") || t.dig("attributes", "proofread")
      if mine.nil? || mine.text != text
        (edited_here.include?(unit.id) ? report.conflicts : report.updates) << [unit, text, username, reviewed]
      elsif reviewed && !mine.reviewed?
        report.reviews << unit
      end
    end
    report
  end

  # Transifex knows the keys as they are in the repo : go through the baseline,
  # so that keys renamed in the tool since still find their unit
  def units_by_repo_key
    @units_by_repo_key ||= begin
      active = Unit.active.index_by(&:id)
      by_baseline = Baseline.current.entries.filter_map { |e| [e["key"], active[e["unit_id"]]] if active[e["unit_id"]] }.to_h
      Unit.active.index_by(&:key).merge(by_baseline)
    end
  end

  # Some Transifex YAML parsers prefix keys with the root language
  def normalize_key(key)
    key.to_s.delete_prefix("#{Language::SOURCE_CODE}.")
  end
end
