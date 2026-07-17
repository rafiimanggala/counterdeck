# Loads the drafted meta-deck counter sheets (db/seeds/meta_counters.json) into
# Deck + CounterRecommendation rows.
#
# A counter entry's "card" field is the human-drafted descriptor, often listing
# several cards in one string ("Effect Veiler / Infinite Impermanence",
# "Cupsy/Cooky/Lollipo/Marshmao Yummy"). Rather than guess at seed time, the
# resolved catalog cards are FROZEN per descriptor in db/seeds/counter_card_links.json
# (regenerate with `rake counters:resolve_links`). Each recommendation keeps the
# descriptor verbatim as its card_name and attaches its resolved card art via:
#   - one card  -> card_id (single staple, shows one face + its banlist badge);
#   - two+ cards -> counter_recommendation_cards join rows (all halves show art);
#   - none       -> stays free text (truly descriptive entries, invented pieces).
# A name fallback (exact -> alias -> case-insensitive) links any freshly added
# descriptor that has no frozen entry yet. Everything imported is status="draft".
class CounterSeedImporter
  SEED_PATH = Rails.root.join("db", "seeds", "meta_counters.json")
  LINKS_PATH = Rails.root.join("db", "seeds", "counter_card_links.json")

  # Common shorthand -> catalog name (downcased keys), used only by the name
  # fallback for descriptors with no frozen link entry.
  ALIASES = {
    "maxx c" => 'Maxx "C"',
    'maxx "c"' => 'Maxx "C"',
    "imperm" => "Infinite Impermanence",
    "veiler" => "Effect Veiler",
    "ash" => "Ash Blossom & Joyous Spring",
    "ash blossom" => "Ash Blossom & Joyous Spring",
    "belle" => "Ghost Belle & Haunted Mansion",
    "ghost ogre" => "Ghost Ogre & Snow Rabbit",
    "droplet" => "Forbidden Droplet",
    "duster" => "Harpie's Feather Duster",
    "called" => "Called by the Grave",
    "crossout" => "Crossout Designator",
    "nibiru" => "Nibiru, the Primal Being",
    "evenly" => "Evenly Matched",
    "dd crow" => "D.D. Crow",
    "twin twister" => "Twin Twisters"
  }.freeze

  # Looks like a role/strategy description, not a card name (never name-linked).
  DESCRIPTIVE = /
    post-board | enabler | floodgate\ breakers | \bremoval\b | \bline\)?$ |
    \bengine\b | \benablers?\b | level\ \d | \betc\.? | spell-trap\ removal |
    negate-all | tribute\ removal | \bpieces?\b
  /xi

  Result = Struct.new(:decks, :recommendations, :linked, :unlinked, keyword_init: true)

  def initialize(path: SEED_PATH, links_path: LINKS_PATH, logger: Rails.logger)
    @path = path
    @links = File.exist?(links_path) ? JSON.parse(File.read(links_path)) : {}
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
      confidence: entry["confidence"]
    )
    # New decks start as draft, but never downgrade a deck a human already
    # verified: re-seeding refreshes prose/links without undoing verification.
    deck.status ||= "draft"
    deck.save!
    @result.decks += 1

    deck.counter_recommendations.destroy_all
    position = 0
    position = add_recs(deck, entry["key_cards"], CounterRecommendation::KEY_CARD, position) { |c| [ c["card"], c["role"], nil ] }
    position = add_recs(deck, entry["hand_traps"], CounterRecommendation::HAND_TRAP, position) { |c| [ c["card"], c["why"], c["when"] ] }
    add_recs(deck, entry["board_breakers"], CounterRecommendation::BOARD_BREAKER, position) { |c| [ c["card"], c["why"], nil ] }
  end

  def add_recs(deck, items, category, position)
    Array(items).each do |item|
      raw, note, timing = yield(item)
      next if raw.blank?

      cards = resolve_cards(deck.slug, raw)
      rec = deck.counter_recommendations.create!(
        category: category,
        card_id: cards.one? ? cards.first.id : nil,
        card_name: raw,
        note: note,
        timing: timing,
        position: position
      )
      cards.each_with_index { |card, i| rec.counter_recommendation_cards.create!(card: card, position: i) } if cards.size >= 2

      position += 1
      @result.recommendations += 1
      cards.any? ? (@result.linked += 1) : (@result.unlinked += 1)
    end
    position
  end

  # The catalog cards a descriptor resolves to: the frozen link entry first
  # (the authoritative, human-verified resolution), then a deterministic name
  # fallback so a freshly drafted descriptor still links without regeneration.
  def resolve_cards(deck_slug, raw)
    ids = Array(@links.dig(deck_slug, raw))
    cards = ids.filter_map { |id| Card.find_by(ygo_id: id) }.select { |c| c.primary_image&.ygo_image_id }
    return cards if cards.any?

    card = name_fallback(raw)
    card ? [ card ] : []
  end

  # exact -> alias -> case-insensitive. Strips parenthetical notes; never links a
  # role/strategy description. No fuzzy similarity (kept deterministic on purpose).
  def name_fallback(raw)
    name = raw.to_s.gsub(/\s*\([^)]*\)\s*/, " ").strip
    return nil if name.blank? || name.include?("/") || name.match?(DESCRIPTIVE)

    canonical = ALIASES[name.downcase] || name
    Card.find_by(name: canonical) ||
      Card.where("lower(name) = ?", canonical.downcase).first ||
      Card.where("name ILIKE ?", canonical).first
  end
end
