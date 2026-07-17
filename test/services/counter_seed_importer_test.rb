require "test_helper"
require "tempfile"

class CounterSeedImporterTest < ActiveSupport::TestCase
  setup do
    @veiler = card("Effect Veiler", 97268402)
    @imperm = card("Infinite Impermanence", 10045474)
    @ash = card("Ash Blossom & Joyous Spring", 14558127)

    @seed = {
      "counters" => [ {
        "deck_name" => "Importer Spec Deck",
        "archetype" => "Combo", "tier" => "Tier 1",
        "key_cards" => [ { "card" => "Effect Veiler / Infinite Impermanence", "role" => "outs" } ],
        "hand_traps" => [ { "card" => "Ash Blossom & Joyous Spring", "why" => "negate", "when" => "on search" } ],
        "board_breakers" => [ { "card" => "floodgate breakers post-board", "why" => "grind" } ]
      } ]
    }
    @links = { "importer-spec-deck" => { "Effect Veiler / Infinite Impermanence" => [ 97268402, 10045474 ] } }
  end

  test "groups a multi-card descriptor into one rec with join rows for every half" do
    import!
    rec = CounterRecommendation.find_by(card_name: "Effect Veiler / Infinite Impermanence")
    assert_nil rec.card_id, "grouped rec keeps card_id nil so the label is shown, not one card's name"
    assert_equal [ @veiler.id, @imperm.id ], rec.counter_recommendation_cards.order(:position).map(&:card_id)
    assert_equal %w[Effect\ Veiler Infinite\ Impermanence], rec.display_cards.map(&:name)
  end

  test "links a single staple by card_id with no join rows" do
    import!
    rec = CounterRecommendation.find_by(card_name: "Ash Blossom & Joyous Spring")
    assert_equal @ash.id, rec.card_id
    assert_empty rec.counter_recommendation_cards
    assert_equal [ @ash ], rec.display_cards
  end

  test "leaves a role/strategy descriptor as free text" do
    import!
    rec = CounterRecommendation.find_by(card_name: "floodgate breakers post-board")
    assert_nil rec.card_id
    assert_empty rec.display_cards
  end

  test "is idempotent: re-running reproduces the same recs, not duplicates" do
    import!
    import!
    assert_equal 3, Deck.find_by(slug: "importer-spec-deck").counter_recommendations.count
  end

  test "re-seeding never downgrades a human-verified deck back to draft" do
    import!
    deck = Deck.find_by(slug: "importer-spec-deck")
    assert_equal "draft", deck.status, "a freshly imported deck starts as draft"
    deck.update!(status: "verified")
    import!
    assert_equal "verified", deck.reload.status, "re-import must preserve verification"
  end

  private

  def card(name, ygo_id)
    c = Card.create!(ygo_id: ygo_id, name: name, card_kind: "Effect Monster")
    c.card_images.create!(ygo_image_id: ygo_id, image_url: "https://images.ygoprodeck.com/images/cards/#{ygo_id}.jpg")
    c
  end

  def import!
    seed = Tempfile.new([ "seed", ".json" ])
    seed.write(@seed.to_json)
    seed.flush
    links = Tempfile.new([ "links", ".json" ])
    links.write(@links.to_json)
    links.flush
    CounterSeedImporter.new(path: seed.path, links_path: links.path).import
  ensure
    seed&.close!
    links&.close!
  end
end
