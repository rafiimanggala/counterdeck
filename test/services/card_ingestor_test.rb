require "test_helper"

class CardIngestorTest < ActiveSupport::TestCase
  SAMPLE = {
    "id" => 14558127,
    "name" => "Ash Blossom & Joyous Spring",
    "type" => "Effect Monster",
    "frameType" => "effect",
    "desc" => "When a card or effect activates...",
    "atk" => 0, "def" => 1800, "level" => 3,
    "race" => "Zombie", "attribute" => "FIRE", "archetype" => nil,
    "card_sets" => [
      { "set_name" => "Set", "set_code" => "ABC-EN001", "set_rarity" => "Secret Rare", "set_rarity_code" => "(ScR)", "set_price" => "5.00" },
      # exact duplicate printing -> should dedup
      { "set_name" => "Set", "set_code" => "ABC-EN001", "set_rarity" => "Secret Rare", "set_rarity_code" => "(ScR)", "set_price" => "5.00" },
      { "set_name" => "Set2", "set_code" => "DEF-EN002", "set_rarity" => "Common", "set_rarity_code" => "(C)", "set_price" => "0.50" }
    ],
    "card_prices" => [{
      "cardmarket_price" => "1.50", "tcgplayer_price" => "2.00",
      "ebay_price" => "0.00", "amazon_price" => "3.00", "coolstuffinc_price" => "2.50"
    }],
    "card_images" => [{ "id" => 14558127, "image_url" => "http://example/1.jpg" }],
    "banlist_info" => { "ban_tcg" => "Limited" }
  }.freeze

  test "normalizes a card into printings, prices, images, banlist" do
    CardIngestor.new.call([SAMPLE])
    card = Card.find_by(ygo_id: 14558127)

    assert_equal "Ash Blossom & Joyous Spring", card.name
    assert_equal 2, card.printings.count, "duplicate printing should be deduped"
    assert_equal 4, card.prices.count, "zero-priced ebay entry should be skipped"
    assert_equal 1, card.card_images.count
    assert_equal "limited", card.banlist_status("tcg")
    assert_equal "EUR", card.prices.find_by(source: "cardmarket").currency
  end

  test "re-running does not create duplicates" do
    CardIngestor.new.call([SAMPLE])
    counts = -> { [Card.count, Printing.count, Price.count, BanlistEntry.count] }
    before = counts.call
    CardIngestor.new.call([SAMPLE])
    assert_equal before, counts.call
  end
end
