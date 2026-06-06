require "test_helper"

class DeckBuilderTest < ActionDispatch::IntegrationTest
  setup do
    @ash = Card.create!(ygo_id: 14558127, name: "Ash Blossom & Joyous Spring", card_kind: "Effect Monster")
    # A meta deck whose hand-trap counter links to Ash (so a user running Ash covers it).
    @meta = Deck.create!(name: "Branded Despia")
    @meta.counter_recommendations.create!(category: CounterRecommendation::HAND_TRAP, card_name: @ash.name)
  end

  test "create a deck, then it is owned by this session" do
    post user_decks_path, params: { user_deck: { name: "My Deck" } }
    deck = UserDeck.last
    assert_redirected_to user_deck_path(deck)
    assert_equal 1, UserDeck.count
    follow_redirect!
    assert_response :success
  end

  test "add a catalog card returns json, then increment on re-add" do
    post user_decks_path, params: { user_deck: { name: "My Deck" } }
    deck = UserDeck.last

    post user_deck_deck_entries_path(deck), params: { ygo_id: @ash.ygo_id, zone: "main" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["ok"]
    assert_equal @ash.ygo_id, body["ygo_id"]
    assert_equal 1, body["quantity"]
    assert_equal 1, deck.deck_entries.count
    assert_equal 1, deck.deck_entries.first.quantity

    post user_deck_deck_entries_path(deck), params: { ygo_id: @ash.ygo_id, zone: "main" }
    assert_equal 1, deck.deck_entries.count, "re-adding the same card should not duplicate"
    assert_equal 2, deck.deck_entries.first.reload.quantity
  end

  test "matchups endpoint shows a card the user runs as a covered out" do
    post user_decks_path, params: { user_deck: { name: "My Deck" } }
    deck = UserDeck.last
    post user_deck_deck_entries_path(deck), params: { ygo_id: @ash.ygo_id, zone: "main" }

    # Matchups are loaded lazily through a dedicated frame endpoint, not the show body.
    get matchups_user_deck_path(deck)
    assert_response :success
    assert_match(/Branded Despia/, response.body)
    assert_match(/Ash Blossom/, response.body)
  end

  test "update quantity and delete an entry" do
    post user_decks_path, params: { user_deck: { name: "My Deck" } }
    deck = UserDeck.last
    post user_deck_deck_entries_path(deck), params: { ygo_id: @ash.ygo_id, zone: "main" }
    entry = deck.deck_entries.first

    patch user_deck_deck_entry_path(deck, entry), params: { quantity: 3 }
    assert_equal 3, entry.reload.quantity

    delete user_deck_deck_entry_path(deck, entry)
    assert_equal 0, deck.deck_entries.count
  end

  test "a different session cannot edit someone else's deck" do
    post user_decks_path, params: { user_deck: { name: "Mine" } }
    deck = UserDeck.last

    other = open_session
    other.post user_deck_deck_entries_path(deck), params: { ygo_id: @ash.ygo_id, zone: "main" }
    assert_equal 403, other.response.status
    assert_equal 0, deck.deck_entries.count

    other.get user_deck_path(deck)
    other.assert_response :success # viewing is allowed
  end

  test "unknown card add reports an error without 500" do
    post user_decks_path, params: { user_deck: { name: "My Deck" } }
    deck = UserDeck.last
    # ygo_id 0 short-circuits in the provisioner (no network), returns nil -> json error.
    post user_deck_deck_entries_path(deck), params: { ygo_id: 0, zone: "main" }
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_not body["ok"]
    assert_equal 0, deck.deck_entries.count
  end
end
