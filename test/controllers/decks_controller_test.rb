require "test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @veiler = Card.create!(ygo_id: 97268402, name: "Effect Veiler", card_kind: "Effect Monster")
    @veiler.card_images.create!(ygo_image_id: 97268402, image_url: "https://images.ygoprodeck.com/images/cards/97268402.jpg")
    @imperm = Card.create!(ygo_id: 10045474, name: "Infinite Impermanence", card_kind: "Trap Card")
    @imperm.card_images.create!(ygo_image_id: 10045474, image_url: "https://images.ygoprodeck.com/images/cards/10045474.jpg")
    @cue = Card.create!(ygo_id: 16387555, name: "Kewl Tune Cue", card_kind: "Effect Monster")
    @cue.card_images.create!(ygo_image_id: 16387555, image_url: "https://images.ygoprodeck.com/images/cards/16387555.jpg")

    @deck = Deck.create!(
      name: "Test Meta", status: "verified", tier: "Tier 1", archetype: "Combo",
      headline: "A combo deck.", game_plan: "Build a board.",
      interruption_points: [ { "timing" => "On the first search", "action" => "Drop Effect Veiler or Infinite Impermanence." } ],
      plays: [ { "they" => "Summon Kewl Tune Cue.", "you" => "Veiler the search." } ]
    )
    # single-card key
    @deck.counter_recommendations.create!(category: CounterRecommendation::KEY_CARD, card_name: @cue.name)
    # multi-card hand trap: art for BOTH halves
    multi = @deck.counter_recommendations.create!(category: CounterRecommendation::HAND_TRAP, card_name: "Effect Veiler / Infinite Impermanence", card_id: nil)
    multi.counter_recommendation_cards.create!(card: @veiler, position: 0)
    multi.counter_recommendation_cards.create!(card: @imperm, position: 1)
    # invented piece with no catalog card -> monogram placeholder
    @deck.counter_recommendations.create!(category: CounterRecommendation::BOARD_BREAKER, card_name: 'K9-17 "Ripper"', card_id: nil)
  end

  test "index renders" do
    get root_path
    assert_response :success
  end

  test "deck show renders with single, multi-card, and placeholder recs" do
    get deck_path(@deck)
    assert_response :success
    assert_match(/Test Meta/, response.body)
    assert_match(/Effect Veiler \/ Infinite Impermanence/, response.body) # multi-card label kept
    assert_match %r{/card_images/97268402\.jpg}, response.body              # Veiler art
    assert_match %r{/card_images/10045474\.jpg}, response.body              # Imperm art (both halves)
    assert_match(/K9-17/, response.body)                                    # placeholder still labelled
  end

  test "banlist toggle is honoured (uses fmt, not the reserved format param)" do
    get deck_path(@deck, fmt: "tcg")
    assert_response :success
    assert_select "a", text: "TCG"
    get deck_path(@deck, fmt: "md")
    assert_response :success
  end
end
