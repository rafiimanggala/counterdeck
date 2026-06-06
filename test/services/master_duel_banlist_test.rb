require "test_helper"
require "tempfile"

class MasterDuelBanlistTest < ActiveSupport::TestCase
  test "imports MD statuses and detects divergences from TCG" do
    maxx = Card.create!(ygo_id: 1, name: "Maxx \"C\"")
    maxx.banlist_entries.create!(format: "tcg", status: "forbidden")
    ash = Card.create!(ygo_id: 2, name: "Ash Blossom")
    ash.banlist_entries.create!(format: "tcg", status: "unlimited")

    file = Tempfile.new(["md", ".json"])
    file.write({
      source: "test", captured_on: "2026-01-01",
      entries: [
        { name: "Maxx \"C\"", status: "limited" },     # diverges: tcg forbidden vs md limited
        { name: "Ash Blossom", status: "unlimited" },   # same as tcg -> not a divergence
        { name: "Ghost Of Nowhere", status: "limited" } # unmatched
      ]
    }.to_json)
    file.close

    result = MasterDuelBanlist.new(path: file.path).import

    assert_equal 2, result.imported
    assert_equal ["Ghost Of Nowhere"], result.unmatched
    assert_equal "limited", maxx.reload.banlist_status("md")

    diverging = result.divergences.map { |d| d.card.name }
    assert_includes diverging, "Maxx \"C\""
    assert_not_includes diverging, "Ash Blossom"
  ensure
    file&.unlink
  end
end
