require "test_helper"

class BanlistEntryTest < ActiveSupport::TestCase
  test "normalize_status maps YGOPRODeck strings" do
    assert_equal "forbidden", BanlistEntry.normalize_status("Banned")
    assert_equal "limited", BanlistEntry.normalize_status("Limited")
    assert_equal "semi_limited", BanlistEntry.normalize_status("Semi-Limited")
    assert_equal "unlimited", BanlistEntry.normalize_status(nil)
    assert_equal "unlimited", BanlistEntry.normalize_status("whatever")
  end

  test "one entry per format per card" do
    card = Card.create!(ygo_id: 1, name: "X")
    card.banlist_entries.create!(format: "md", status: "limited")
    dup = card.banlist_entries.build(format: "md", status: "forbidden")
    assert_not dup.valid?
  end

  test "rejects invalid format or status" do
    card = Card.create!(ygo_id: 2, name: "Y")
    assert_not card.banlist_entries.build(format: "bogus", status: "limited").valid?
    assert_not card.banlist_entries.build(format: "tcg", status: "bogus").valid?
  end
end
