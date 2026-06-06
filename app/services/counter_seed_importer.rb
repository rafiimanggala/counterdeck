# Loads the drafted meta-deck counter data (db/seeds/meta_counters.json) into
# Deck + CounterRecommendation rows. Each counter card is linked to a catalog
# Card when the name matches; otherwise the free-text name is kept so Rafii can
# review/fix it later. Everything imported is marked status="draft" pending
# human verification (see the admin "verify" action).
class CounterSeedImporter
  SEED_PATH = Rails.root.join("db", "seeds", "meta_counters.json")

  Result = Struct.new(:decks, :recommendations, :linked, :unlinked, keyword_init: true)

  def initialize(path: SEED_PATH, logger: Rails.logger)
    @path = path
    @logger = logger
    @result = Result.new(decks: 0, recommendations: 0, linked: 0, unlinked: 0)
  end

  def import
    data = JSON.parse(File.read(@path))
    Array(data["counters"]).each { |entry| import_deck(entry) }
    @result
  end

  private

  def import_deck(entry)
    deck = Deck.find_or_initialize_by(slug: entry["deck_name"].to_s.parameterize)
    deck.assign_attributes(
      name: entry["deck_name"],
      archetype: entry["archetype"],
      tier: entry["tier"],
      formats: Array(entry["formats"]).join(", "),
      game_plan: entry["game_plan"],
      going_first_vs_second: entry["going_first_vs_second"],
      beginner_explanation: entry["beginner_explanation"],
      interruption_points: Array(entry["interruption_points"]),
      confidence: entry["confidence"],
      status: "draft"
    )
    deck.save!
    @result.decks += 1

    deck.counter_recommendations.destroy_all
    position = 0
    position = add_recs(deck, entry["key_cards"], CounterRecommendation::KEY_CARD, position) { |c| [c["card"], c["role"], nil] }
    position = add_recs(deck, entry["hand_traps"], CounterRecommendation::HAND_TRAP, position) { |c| [c["card"], c["why"], c["when"]] }
    add_recs(deck, entry["board_breakers"], CounterRecommendation::BOARD_BREAKER, position) { |c| [c["card"], c["why"], nil] }
  end

  def add_recs(deck, items, category, position)
    Array(items).each do |item|
      card_name, note, timing = yield(item)
      next if card_name.blank?

      card = match_card(card_name)
      deck.counter_recommendations.create!(
        category: category,
        card: card,
        card_name: card_name,
        note: note,
        timing: timing,
        position: position
      )
      position += 1
      @result.recommendations += 1
      card ? (@result.linked += 1) : (@result.unlinked += 1)
    end
    position
  end

  # Exact, then case-insensitive match against the catalog.
  def match_card(name)
    Card.find_by(name: name) || Card.where("name ILIKE ?", name).first
  end
end
