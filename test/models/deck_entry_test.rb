require "test_helper"

class DeckEntryTest < ActiveSupport::TestCase
  setup do
    @deck = UserDeck.create!(name: "D", owner_token: "t1")
    @card = Card.create!(ygo_id: 14558127, name: "Ash Blossom & Joyous Spring")
  end

  test "quantity is capped at 3 and must be positive" do
    assert @deck.deck_entries.build(card: @card, zone: "main", quantity: 3).valid?
    assert_not @deck.deck_entries.build(card: @card, zone: "main", quantity: 4).valid?
    assert_not @deck.deck_entries.build(card: @card, zone: "main", quantity: 0).valid?
  end

  test "rejects an invalid zone" do
    assert_not @deck.deck_entries.build(card: @card, zone: "graveyard", quantity: 1).valid?
  end

  test "same card cannot duplicate within a zone but may exist in another" do
    @deck.deck_entries.create!(card: @card, zone: "main", quantity: 1)
    dup = @deck.deck_entries.build(card: @card, zone: "main", quantity: 1)
    assert_not dup.valid?
    other_zone = @deck.deck_entries.build(card: @card, zone: "side", quantity: 1)
    assert other_zone.valid?
  end
end
