require "test_helper"

class DeckTest < ActiveSupport::TestCase
  test "auto-generates a slug from the name" do
    deck = Deck.create!(name: "Sky Striker Control")
    assert_equal "sky-striker-control", deck.slug
    assert_equal deck.slug, deck.to_param
  end

  test "slug is unique" do
    Deck.create!(name: "Branded")
    dup = Deck.new(name: "Branded")
    assert_not dup.valid?
  end

  test "defaults to draft and validates status" do
    deck = Deck.create!(name: "Foo")
    assert_equal "draft", deck.status
    deck.status = "bogus"
    assert_not deck.valid?
  end

  test "interruption_points_text round-trips to structured json" do
    deck = Deck.create!(name: "Bar")
    deck.interruption_points_text = "On Cue summon :: Ash it\nAt 5th summon :: Nibiru"
    deck.save!
    assert_equal 2, deck.interruption_points.size
    assert_equal "On Cue summon", deck.interruption_points.first["timing"]
    assert_equal "Ash it", deck.interruption_points.first["action"]
    assert_includes deck.interruption_points_text, "Nibiru"
  end

  test "groups recommendations by category" do
    deck = Deck.create!(name: "Baz")
    deck.counter_recommendations.create!(category: "key_card", card_name: "A")
    deck.counter_recommendations.create!(category: "hand_trap", card_name: "B")
    deck.counter_recommendations.create!(category: "board_breaker", card_name: "C")
    assert_equal 1, deck.key_cards.size
    assert_equal 1, deck.hand_traps.size
    assert_equal 1, deck.board_breakers.size
  end
end
