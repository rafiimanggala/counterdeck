require "test_helper"

class CounterImpactTest < ActiveSupport::TestCase
  setup do
    @deck = Deck.create!(name: "Test Meta")
    @ash = Card.create!(ygo_id: 14558127, name: "Ash Blossom & Joyous Spring", card_kind: "Tuner Monster")
    @generic = Card.create!(ygo_id: 99999001, name: "Generic Trap", card_kind: "Trap Card")
  end

  def rec(category:, card:, note: nil, timing: nil, impact: nil)
    @deck.counter_recommendations.create!(category: category, card: card, note: note, timing: timing, impact: impact)
  end

  test "explicit override wins over the heuristic" do
    r = rec(category: CounterRecommendation::HAND_TRAP, card: @ash, note: "situational, easily played around", impact: "high")
    assert_equal :high, CounterImpact.tier(r)
  end

  test "ignore_override returns the pure heuristic" do
    r = rec(category: CounterRecommendation::HAND_TRAP, card: @ash, note: "best hand trap, shuts off the combo", impact: "low")
    assert_equal :low, CounterImpact.tier(r)
    assert_equal :high, CounterImpact.tier(r, ignore_override: true)
  end

  test "allowlisted staple with a strong note is high" do
    r = rec(category: CounterRecommendation::HAND_TRAP, card: @ash, note: "Best hand trap vs this deck, shuts down the combo")
    assert_equal :high, CounterImpact.tier(r)
  end

  test "weakness keywords pull a card to low" do
    r = rec(category: CounterRecommendation::HAND_TRAP, card: @generic, note: "situational and easily played around")
    assert_equal :low, CounterImpact.tier(r)
  end

  test "board breakers outrank hand traps at baseline" do
    bb = rec(category: CounterRecommendation::BOARD_BREAKER, card: @generic, note: "clears the board")
    ht = rec(category: CounterRecommendation::HAND_TRAP, card: @generic, note: "negates a summon")
    assert_operator CounterImpact.weight(CounterImpact.tier(bb)), :>=, CounterImpact.weight(CounterImpact.tier(ht))
  end

  test "a forbidden card is demoted to low when a format is given" do
    @ash.banlist_entries.create!(format: "md", status: BanlistEntry::FORBIDDEN)
    r = rec(category: CounterRecommendation::HAND_TRAP, card: @ash, note: "Best hand trap, shuts off the combo")
    assert_equal :high, CounterImpact.tier(r, format: "tcg")
    assert_equal :low,  CounterImpact.tier(r, format: "md")
  end

  test "label and weight helpers" do
    assert_equal "Stops their combo", CounterImpact.label(:high)
    assert_equal 3, CounterImpact.weight(:high)
    assert_equal 1, CounterImpact.weight(:low)
  end
end
