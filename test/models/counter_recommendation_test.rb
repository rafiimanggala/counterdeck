require "test_helper"

class CounterRecommendationTest < ActiveSupport::TestCase
  setup do
    @deck = Deck.create!(name: "Test Deck")
    @card = Card.create!(ygo_id: 14558127, name: "Ash Blossom & Joyous Spring")
  end

  test "autolinks to a catalog card by name" do
    rec = @deck.counter_recommendations.create!(
      category: "hand_trap", card_name: "Ash Blossom & Joyous Spring"
    )
    assert_equal @card, rec.card
  end

  test "keeps free-text name when no card matches" do
    rec = @deck.counter_recommendations.create!(
      category: "hand_trap", card_name: "Totally Unknown Card"
    )
    assert_nil rec.card
    assert_equal "Totally Unknown Card", rec.display_name
  end

  test "requires a card or a name" do
    rec = @deck.counter_recommendations.build(category: "hand_trap")
    assert_not rec.valid?
  end

  test "rejects invalid category" do
    rec = @deck.counter_recommendations.build(category: "bogus", card_name: "X")
    assert_not rec.valid?
  end
end
