require "test_helper"

class UserDeckTest < ActiveSupport::TestCase
  setup do
    @card = Card.create!(ygo_id: 14558127, name: "Ash Blossom & Joyous Spring", card_kind: "Effect Monster")
  end

  test "auto-generates a slug from the name" do
    deck = UserDeck.create!(name: "My Snake-Eye", owner_token: "t1")
    assert_equal "my-snake-eye", deck.slug
  end

  test "slug stays unique across decks with the same name" do
    a = UserDeck.create!(name: "Tenpai", owner_token: "t1")
    b = UserDeck.create!(name: "Tenpai", owner_token: "t1")
    assert_not_equal a.slug, b.slug
  end

  test "card_count sums quantities per zone" do
    deck = UserDeck.create!(name: "D", owner_token: "t1")
    deck.deck_entries.create!(card: @card, zone: "main", quantity: 3)
    assert_equal 3, deck.card_count("main")
    assert_equal 0, deck.card_count("side")
    assert_equal 3, deck.card_count
  end

  test "card_id_set and ownership" do
    deck = UserDeck.create!(name: "D", owner_token: "secret")
    deck.deck_entries.create!(card: @card, zone: "main", quantity: 1)
    assert_includes deck.card_id_set, @card.id
    assert deck.owned_by?("secret")
    assert_not deck.owned_by?("other")
    assert_not deck.owned_by?(nil)
  end
end
