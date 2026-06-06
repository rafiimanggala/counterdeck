# The headline feature: given a user-built deck, work out which of its cards
# already counter each meta deck. For every meta Deck we partition its linked
# counter cards (hand traps = HOLD, board breakers = BREAK) into:
#   have    -> cards the user is already running (with their copy count)
#   missing -> recommended counters the user has not added yet
# Matchups are sorted best-covered first so the user sees their strong matchups.
class DeckMatchup
  COUNTER_CATEGORIES = [CounterRecommendation::HAND_TRAP, CounterRecommendation::BOARD_BREAKER].freeze

  HaveItem = Struct.new(:rec, :quantity, keyword_init: true)
  Matchup  = Struct.new(:deck, :have, :missing, keyword_init: true) do
    def total = have.size + missing.size
    def coverage_pct = total.zero? ? 0 : (have.size * 100.0 / total).round
    def have?   = have.any?
    def covered? = coverage_pct >= 50
  end

  def initialize(user_deck)
    @user_deck = user_deck
    @my_card_ids = user_deck.card_id_set
    @qty_by_card = user_deck.deck_entries.group_by(&:card_id).transform_values { |es| es.sum(&:quantity) }
  end

  def matchups
    Deck.includes(counter_recommendations: { card: :card_images })
        .map { |deck| build(deck) }
        .reject { |m| m.total.zero? }
        .sort_by { |m| [-m.coverage_pct, m.deck.name.to_s] }
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
      if @my_card_ids.include?(rec.card_id)
        have << HaveItem.new(rec: rec, quantity: @qty_by_card[rec.card_id])
      else
        missing << rec
      end
    end

    Matchup.new(deck: deck, have: have, missing: missing)
  end
end
