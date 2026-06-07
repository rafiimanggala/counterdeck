require "test_helper"

class PrintingTest < ActiveSupport::TestCase
  test "classify maps a secret rare to a foil secret tier" do
    v = Printing.classify(set_rarity: "Secret Rare", set_code: "ROTD-EN001", set_name: "Rise of the Duelist")
    assert_equal "secret", v[:rarity_tier]
    assert v[:foil]
    assert_not v[:promo]
    assert_equal "unlimited", v[:edition]
  end

  test "classify treats common as a non-foil standard tier" do
    v = Printing.classify(set_rarity: "Common", set_code: "LOB-001")
    assert_equal "standard", v[:rarity_tier]
    assert_not v[:foil]
  end

  test "classify ranks compound rarities before plain rare" do
    assert_equal "super", Printing.classify(set_rarity: "Super Rare")[:rarity_tier]
    assert_equal "ultra", Printing.classify(set_rarity: "Ultra Rare")[:rarity_tier]
    assert_equal "rare", Printing.classify(set_rarity: "Rare")[:rarity_tier]
  end

  test "classify flags promo set codes and promo rarities" do
    assert Printing.classify(set_rarity: "Ultra Rare", set_code: "OP01-EN001")[:promo]
    assert Printing.classify(set_rarity: "Promo", set_code: "ZZZ-001")[:promo]
    assert_not Printing.classify(set_rarity: "Ultra Rare", set_code: "ROTD-EN001")[:promo]
  end

  test "classify detects 1st edition from the set name" do
    v = Printing.classify(set_rarity: "Rare", set_name: "Legend of Blue Eyes White Dragon (1st Edition)")
    assert_equal "1st", v[:edition]
  end

  test "rejects an invalid edition" do
    card = Card.create!(ygo_id: 7000001, name: "Variant Test A")
    printing = card.printings.build(set_code: "X-1", edition: "platinum")
    assert_not printing.valid?
    assert_includes printing.errors[:edition], "is not included in the list"
  end

  test "same set and rarity but different editions coexist" do
    card = Card.create!(ygo_id: 7000002, name: "Variant Test B")
    card.printings.create!(set_code: "LOB-001", set_rarity: "Ultra Rare", edition: "unlimited", rarity_tier: "ultra", foil: true)
    other = card.printings.build(set_code: "LOB-001", set_rarity: "Ultra Rare", edition: "1st", rarity_tier: "ultra", foil: true)
    assert other.valid?, other.errors.full_messages.to_sentence
  end

  test "a duplicate set, rarity, and edition is rejected" do
    card = Card.create!(ygo_id: 7000003, name: "Variant Test C")
    card.printings.create!(set_code: "LOB-001", set_rarity: "Ultra Rare", edition: "unlimited")
    dup = card.printings.build(set_code: "LOB-001", set_rarity: "Ultra Rare", edition: "unlimited")
    assert_not dup.valid?
  end
end
