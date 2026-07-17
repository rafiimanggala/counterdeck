require "test_helper"

class BattlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ash = Card.create!(ygo_id: 14558127, name: "Ash Blossom & Joyous Spring", card_kind: "Effect Monster")
    @meta = Deck.create!(
      name: "Branded Despia", status: "verified", tier: "Tier 1", archetype: "Despia",
      headline: "Builds a board from one card.", game_plan: "Grind you out with Mirrorjade.",
      plays: [ { "they" => "Play Branded Fusion.", "you" => "Ash the Fusion." } ],
      interruption_points: [ { "timing" => "On Branded Fusion", "action" => "Drop Ash." } ]
    )
    @meta.counter_recommendations.create!(category: CounterRecommendation::HAND_TRAP, card_name: @ash.name)
    @meta.counter_recommendations.create!(category: CounterRecommendation::KEY_CARD, card_name: @ash.name)
  end

  def make_owned_deck_with_ash
    post user_decks_path, params: { user_deck: { name: "My Deck" } }
    deck = UserDeck.last
    post user_deck_deck_entries_path(deck), params: { ygo_id: @ash.ygo_id, zone: "main" }
    deck
  end

  test "battle page renders with no picks (no decks yet) and prompts to build one" do
    get battle_path
    assert_response :success
    assert_match(/Build a deck to start a battle/, response.body)
  end

  test "battle with an owned deck and an enemy shows the head to head matchup" do
    make_owned_deck_with_ash

    get battle_path(vs: @meta.slug, banlist: "tcg")
    assert_response :success
    assert_match(/Real Battle/, response.body)
    assert_match(/Branded Despia/, response.body)        # enemy identity
    assert_match(/Their board/, response.body)           # threat board section
    assert_match(/Your answers/, response.body)          # answer hand section
    assert_match(/Ash Blossom/, response.body)           # the out the user runs
    assert_match(/How the turn goes/, response.body)     # turn spine (plays)
    assert_match(/When to disrupt/, response.body)       # interruption points
  end

  test "battle defaults to the visitor's most recent deck when mine is omitted" do
    make_owned_deck_with_ash
    get battle_path(vs: @meta.slug)
    assert_response :success
    assert_match(/My Deck/, response.body)
  end

  test "battle without an enemy shows your deck and the pick-an-enemy prompt" do
    make_owned_deck_with_ash
    get battle_path
    assert_response :success
    assert_match(/Pick an enemy/, response.body)
  end

  test "an unknown banlist param falls back to tcg without error" do
    make_owned_deck_with_ash
    get battle_path(vs: @meta.slug, banlist: "bogus")
    assert_response :success
  end

  test "an unknown enemy slug renders the page without the matchup" do
    make_owned_deck_with_ash
    get battle_path(vs: "does-not-exist")
    assert_response :success
    assert_match(/Pick an enemy/, response.body)
  end
end
