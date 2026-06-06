require "test_helper"

class CardTest < ActiveSupport::TestCase
  test "requires ygo_id and name" do
    card = Card.new
    assert_not card.valid?
    assert_includes card.errors.attribute_names, :ygo_id
    assert_includes card.errors.attribute_names, :name
  end

  test "ygo_id is unique" do
    Card.create!(ygo_id: 111, name: "A")
    dup = Card.new(ygo_id: 111, name: "B")
    assert_not dup.valid?
  end

  test "banlist_status defaults to unlimited and reflects entries" do
    card = Card.create!(ygo_id: 222, name: "Maxx C")
    assert_equal "unlimited", card.banlist_status("tcg")

    card.banlist_entries.create!(format: "tcg", status: "forbidden")
    assert_equal "forbidden", card.reload.banlist_status("tcg")
    assert_equal "unlimited", card.banlist_status("md")
  end

  test "search_name is case-insensitive and partial" do
    card = Card.create!(ygo_id: 333, name: "Ash Blossom & Joyous Spring")
    assert_includes Card.search_name("ash blossom"), card
    assert_empty Card.search_name("nonexistent card xyz")
  end
end
