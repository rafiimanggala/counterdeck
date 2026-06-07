# Merges card records from MULTIPLE sources into one canonical row, the way a
# multi-game catalog (Pokemon + MTG + Lorcana + ...) must harmonize feeds that
# disagree. Each source yields SourceRecords keyed by a natural key. For every
# reconciled field the highest-priority source with a non-nil value wins, and any
# cross-source disagreement is recorded as a conflict in the card's JSONB
# metadata. The catalog therefore never silently picks one value and hides the
# divergence: the provenance and the conflict are both queryable afterwards.
#
# A source is any object responding to #records -> Array<SourceRecord>.
# Adapters for the common cases are provided (YgoprodeckAdapter, HashAdapter).
class DataReconciler
  SourceRecord = Struct.new(:source, :priority, :natural_key, :attributes, keyword_init: true)
  Result = Struct.new(:cards_upserted, :conflicts, :stats, keyword_init: true)

  # Fields we trust no single source on; reconciled across all sources.
  RECONCILED_FIELDS = %w[
    name card_kind ygo_attribute race atk defense level archetype card_text
  ].freeze

  def initialize(sources:, logger: Rails.logger)
    @sources = Array(sources)
    @logger = logger
  end

  # Pure: returns { natural_key => { attributes:, provenance:, conflicts:, sources: } }.
  def reconcile
    collect_records.group_by(&:natural_key).transform_values { |records| merge_group(records) }
  end

  # Upserts the reconciled cards and persists provenance + conflicts to metadata.
  # Idempotent: re-running with the same sources produces the same rows.
  def apply!
    resolutions = reconcile
    divergence_by_source = Hash.new(0)
    conflicts_total = 0

    resolutions.each do |natural_key, resolution|
      upsert_card(natural_key, resolution)
      conflicts_total += resolution[:conflicts].size
      resolution[:conflicts].each { |c| divergence_by_source[c[:losing_source]] += 1 if c[:losing_source] }
    end

    Result.new(
      cards_upserted: resolutions.size,
      conflicts: conflicts_total,
      stats: { sources: @sources.size, divergence_by_source: divergence_by_source }
    )
  end

  private

  def collect_records
    @sources.flat_map do |adapter|
      Array(adapter.records)
    rescue => e
      @logger.error("[DataReconciler] source #{adapter.class} failed: #{e.class} #{e.message}")
      []
    end
  end

  # For one natural key: pick each field from the highest-priority source that
  # supplies a non-nil value, and flag fields where sources actually disagree.
  def merge_group(records)
    ranked = records.sort_by { |r| -r.priority.to_i }
    attributes = {}
    provenance = {}
    conflicts = []

    RECONCILED_FIELDS.each do |field|
      present = ranked.reject { |r| r.attributes[field].nil? }
      next if present.empty?

      winner = present.first
      attributes[field] = winner.attributes[field]
      provenance[field] = winner.source

      distinct_values = present.map { |r| r.attributes[field] }.uniq
      next if distinct_values.size <= 1

      loser = present.find { |r| r.attributes[field] != winner.attributes[field] }
      conflicts << {
        field: field,
        chosen: winner.attributes[field],
        chosen_source: winner.source,
        losing_source: loser&.source,
        values: present.to_h { |r| [r.source, r.attributes[field]] }
      }
    end

    {
      attributes: attributes,
      provenance: provenance,
      conflicts: conflicts,
      sources: records.map(&:source).uniq
    }
  end

  def upsert_card(natural_key, resolution)
    card = Card.find_or_initialize_by(ygo_id: natural_key)
    card.assign_attributes(resolution[:attributes].slice(*Card.column_names))
    card.metadata = card.metadata.merge(
      "provenance" => resolution[:provenance],
      "conflicts" => resolution[:conflicts].map { |c| c.transform_keys(&:to_s) },
      "sources" => resolution[:sources]
    )
    card.save!
    card
  end

  # ---- source adapters --------------------------------------------------

  # Wraps raw YGOPRODeck card hashes (string keys) as the baseline source.
  class YgoprodeckAdapter
    DEFAULT_PRIORITY = 50

    def initialize(api_cards, priority: DEFAULT_PRIORITY)
      @api_cards = api_cards
      @priority = priority
    end

    def records
      Array(@api_cards).map do |data|
        SourceRecord.new(
          source: "ygoprodeck",
          priority: @priority,
          natural_key: data["id"],
          attributes: {
            "name" => data["name"], "card_kind" => data["type"],
            "ygo_attribute" => data["attribute"], "race" => data["race"],
            "atk" => data["atk"], "defense" => data["def"], "level" => data["level"],
            "archetype" => data["archetype"], "card_text" => data["desc"]
          }
        )
      end
    end
  end

  # Generic adapter for curated overrides, scrapes, or manual corrections.
  # rows: [{ natural_key:, attributes: { "atk" => 2600, ... } }, ...]
  class HashAdapter
    def initialize(source:, priority:, rows:)
      @source = source
      @priority = priority
      @rows = Array(rows)
    end

    def records
      @rows.map do |row|
        SourceRecord.new(
          source: @source,
          priority: @priority,
          natural_key: row[:natural_key] || row["natural_key"],
          attributes: (row[:attributes] || row["attributes"] || {}).transform_keys(&:to_s)
        )
      end
    end
  end
end
