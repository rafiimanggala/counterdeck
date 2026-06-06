require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    @ash = Card.create!(
      ygo_id: 14558127, name: "Ash Blossom & Joyous Spring",
      card_kind: "Effect Monster", frame_type: "effect",
      ygo_attribute: "FIRE", race: "Zombie", level: 3, atk: 0, defense: 1800,
      archetype: nil, card_text: "When a card or effect activates..."
    )
  end

  test "catalog index returns a slim json row per card" do
    get cards_index_path
    assert_response :success
    rows = JSON.parse(response.body)
    row = rows.find { |r| r["ygo_id"] == @ash.ygo_id }
    assert row, "Ash should be in the catalog index"
    assert_equal "Ash Blossom & Joyous Spring", row["name"]
    assert_equal "FIRE", row["attr"]
    assert_equal 3, row["level"]
    assert_equal 1800, row["def"]
  end

  test "card detail renders the full description partial" do
    get card_path(@ash.ygo_id)
    assert_response :success
    assert_match(/Ash Blossom &amp; Joyous Spring/, response.body)
    assert_match(/When a card or effect activates/, response.body)
    assert_match(/FIRE/, response.body)
  end

  test "card detail for an unknown id without network is not found" do
    # ygo_id 0 short-circuits in the provisioner (no network call).
    get card_path(0)
    assert_response :not_found
  end
end
