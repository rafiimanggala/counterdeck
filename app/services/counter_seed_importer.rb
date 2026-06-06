# Loads the drafted meta-deck counter data (db/seeds/meta_counters.json) into
# Deck + CounterRecommendation rows.
#
# A counter entry's "card" field is often a shorthand or lists several cards in
# one string ("Effect Veiler / Infinite Impermanence", "Kaijus / Lava Golem").
# This importer SPLITS those into one recommendation per card so each links to a
# catalog Card and shows its own banlist badge, and resolves names via:
#   exact -> alias -> case-insensitive -> pg_trgm fuzzy.
# Truly descriptive entries ("floodgate breakers post-board") stay as free text.
# Everything imported is status="draft" pending human verification.
class CounterSeedImporter
  SEED_PATH = Rails.root.join("db", "seeds", "meta_counters.json")
  FUZZY_THRESHOLD = 0.55

  # Common shorthand -> catalog name. Keys are downcased.
  ALIASES = {
    "maxx c" => 'Maxx "C"',
    'maxx "c"' => 'Maxx "C"',
    "imperm" => "Infinite Impermanence",
    "infinite imperm" => "Infinite Impermanence",
    "veiler" => "Effect Veiler",
    "ash" => "Ash Blossom & Joyous Spring",
    "ash blossom" => "Ash Blossom & Joyous Spring",
    "belle" => "Ghost Belle & Haunted Mansion",
    "ghost ogre" => "Ghost Ogre & Snow Rabbit",
    "mst" => "Mystical Space Typhoon",
    "ttt" => "Triple Tactics Talent",
    "droplet" => "Forbidden Droplet",
    "duster" => "Harpie's Feather Duster",
    "harpie's feather duster" => "Harpie's Feather Duster",
    "called" => "Called by the Grave",
    "crossout" => "Crossout Designator",
    "nibiru" => "Nibiru, the Primal Being",
    "lava golem" => "Lava Golem",
    "evenly" => "Evenly Matched",
    "drnm" => "Dark Ruler No More",
    "super poly" => "Super Polymerization",
    # Fix common misspellings in the drafted seed so high-traffic staples link.
    "dd crow" => "D.D. Crow",
    "d.d crow" => "D.D. Crow",
    "nibiru, the primordial being" => "Nibiru, the Primal Being",
    "nibiru the primal being" => "Nibiru, the Primal Being",
    "ghost bell & haunted mansion" => "Ghost Belle & Haunted Mansion",
    "ash blossom & spring breeze" => "Ash Blossom & Joyous Spring",
    "ghost ogre & snow rabbit" => "Ghost Ogre & Snow Rabbit",
    "twin twister" => "Twin Twisters"
  }.freeze

  # Looks like a role/strategy description, not a single card name.
  DESCRIPTIVE = /
    post-board | enabler | floodgate\ breakers | \bremoval\b | \bline\)?$ |
    \bengine\b | \benablers?\b | level\ \d | \betc\.? | spell-trap\ removal |
    negate-all | tribute\ removal | \bpieces?\b
  /xi

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
      raw, note, timing = yield(item)
      next if raw.blank?

      names = split_names(raw)
      names.each_with_index do |name, idx|
        card = match_card(name)
        deck.counter_recommendations.create!(
          category: category,
          card: card,
          card_name: name,
          # Keep the explanation on the first split part only (the rest render adjacent).
          note: idx.zero? ? note : nil,
          timing: idx.zero? ? timing : nil,
          position: position
        )
        position += 1
        @result.recommendations += 1
        card ? (@result.linked += 1) : (@result.unlinked += 1)
      end
    end
    position
  end

  # "Effect Veiler / Infinite Impermanence (when they search)" -> ["Effect Veiler", "Infinite Impermanence"]
  # A descriptive blob is returned whole (one element) so it stays as free text.
  def split_names(raw)
    base = raw.to_s.gsub(/\s*\([^)]*\)\s*/, " ").strip   # drop parenthetical notes
    return [raw.strip] if base.match?(DESCRIPTIVE)         # description: keep verbatim

    parts = base.split(%r{\s*/\s*}).map(&:strip).reject(&:blank?)
    parts = [base] if parts.empty?
    # Drop overly long "parts" that are clearly prose, not card names.
    parts.map { |p| p.length > 45 ? p : p }.reject(&:blank?)
  end

  # exact -> alias -> case-insensitive -> pg_trgm fuzzy. Never links descriptions.
  def match_card(name)
    return nil if name.to_s.match?(DESCRIPTIVE)

    canonical = ALIASES[name.downcase.strip] || name
    Card.find_by(name: canonical) ||
      Card.where("lower(name) = ?", canonical.downcase).first ||
      Card.where("name ILIKE ?", canonical).first ||
      fuzzy(canonical)
  end

  def fuzzy(name)
    quoted = ActiveRecord::Base.connection.quote(name)
    Card.where("similarity(name, ?) >= ?", name, FUZZY_THRESHOLD)
        .order(Arel.sql("similarity(name, #{quoted}) DESC"))
        .first
  end
end
