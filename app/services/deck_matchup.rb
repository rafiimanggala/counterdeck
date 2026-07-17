# The headline feature: given a user-built deck, work out which of its cards
# already counter each meta deck. For every meta Deck we partition its linked
# counter cards (hand traps = HOLD, board breakers = BREAK) into:
#   have    -> cards the user is already running (with their copy count)
#   missing -> recommended counters the user has not added yet
# Each out is tiered by impact (CounterImpact: high/medium/low) so coverage can
# be weighted - owning the single best out matters more than owning three weak
# ones. Matchups are sorted best-(weighted)-covered first.
class DeckMatchup
  COUNTER_CATEGORIES = [ CounterRecommendation::HAND_TRAP, CounterRecommendation::BOARD_BREAKER ].freeze

  # A high-impact out whose note reads like it shuts off the deck's core engine.
  ENGINE_RE = /shuts? off|shuts? down|turns? off|\bengine\b|\bcore\b|their key|key card|omni-negate|stop the combo/i

  HaveItem    = Struct.new(:rec, :quantity, :tier, keyword_init: true)
  MissingItem = Struct.new(:rec, :tier, keyword_init: true)

  Matchup = Struct.new(:deck, :have, :missing, keyword_init: true) do
    def total = have.size + missing.size
    def coverage_pct = total.zero? ? 0 : (have.size * 100.0 / total).round
    def have? = have.any?

    # Impact-weighted coverage: owning the best outs counts for more.
    def weighted_total = (have + missing).sum { |i| CounterImpact.weight(i.tier) }
    def weighted_have  = have.sum { |i| CounterImpact.weight(i.tier) }
    def weighted_coverage_pct = weighted_total.zero? ? 0 : (weighted_have * 100.0 / weighted_total).round
    def covered? = weighted_coverage_pct >= 50

    def high_have_count = have.count { |i| i.tier == :high }
    def answers_key_card?
      have.any? { |i| i.tier == :high && i.rec.note.to_s.match?(ENGINE_RE) }
    end

    # Counts per tier split into have/missing, ordered high -> low, for the bar.
    def tier_split
      %i[high medium low].map do |tier|
        {
          tier: tier,
          have: have.count { |i| i.tier == tier },
          missing: missing.count { |i| i.tier == tier }
        }
      end
    end
  end

  def initialize(user_deck, format: nil)
    @user_deck = user_deck
    @format = format
    @my_card_ids = user_deck.card_id_set
    @qty_by_card = user_deck.deck_entries.group_by(&:card_id).transform_values { |es| es.sum(&:quantity) }
  end

  def matchups
    Deck.verified.includes(counter_recommendations: { card: :card_images })
        .map { |deck| build(deck) }
        .reject { |m| m.total.zero? }
        .sort_by { |m| [ -m.weighted_coverage_pct, -m.high_have_count, m.deck.name.to_s ] }
  end

  # The head-to-head: the single matchup of this user deck against one meta deck
  # (powers the Real Battle screen). Returns nil if there is nothing to compare.
  def matchup_for(deck)
    return nil unless deck

    m = build(deck)
    m.total.zero? ? nil : m
  end

  private

  def build(deck)
    have = []
    missing = []
    seen = Set.new

    deck.counter_recommendations.each do |rec|
      next unless COUNTER_CATEGORIES.include?(rec.category) && rec.card_id
      next if seen.include?(rec.card_id)

      seen << rec.card_id
      tier = CounterImpact.tier(rec, format: @format)
      if @my_card_ids.include?(rec.card_id)
        have << HaveItem.new(rec: rec, quantity: @qty_by_card[rec.card_id], tier: tier)
      else
        missing << MissingItem.new(rec: rec, tier: tier)
      end
    end

    have.sort_by!    { |i| [ -CounterImpact.weight(i.tier), i.rec.display_name.to_s ] }
    missing.sort_by! { |i| [ -CounterImpact.weight(i.tier), i.rec.display_name.to_s ] }
    Matchup.new(deck: deck, have: have, missing: missing)
  end
end
