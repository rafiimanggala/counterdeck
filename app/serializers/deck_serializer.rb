# Serializes a meta Deck plus its grouped counter recommendations.
class DeckSerializer
  def initialize(deck, detailed: false)
    @deck = deck
    @detailed = detailed
  end

  def as_json(*)
    base = {
      slug: @deck.slug,
      name: @deck.name,
      archetype: @deck.archetype,
      tier: @deck.tier,
      formats: @deck.format_list,
      status: @deck.status,
      confidence: @deck.confidence
    }
    return base unless @detailed

    base.merge(
      game_plan: @deck.game_plan,
      going_first_vs_second: @deck.going_first_vs_second,
      beginner_explanation: @deck.beginner_explanation,
      interruption_points: @deck.interruption_points,
      key_cards: @deck.key_cards.map { |r| rec(r) },
      hand_traps: @deck.hand_traps.map { |r| rec(r) },
      board_breakers: @deck.board_breakers.map { |r| rec(r) }
    )
  end

  private

  def rec(r)
    {
      card: r.display_name,
      card_id: r.card_id,
      note: r.note,
      timing: r.timing
    }
  end
end
