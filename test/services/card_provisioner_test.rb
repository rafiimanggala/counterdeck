require "test_helper"

class CardProvisionerTest < ActiveSupport::TestCase
  # Stub client so tests never touch the network.
  class StubClient
    def initialize(remote: []) = @remote = remote
    def cards(**) = @remote
  end

  setup do
    @ash = Card.create!(ygo_id: 14558127, name: "Ash Blossom & Joyous Spring", card_kind: "Effect Monster")
  end

  test "search returns local catalog matches" do
    results = CardProvisioner.new(client: StubClient.new).search("ash")
    assert results.any? { |s| s.ygo_id == @ash.ygo_id && s.in_catalog? }
  end

  test "search ignores queries shorter than 2 chars" do
    assert_empty CardProvisioner.new(client: StubClient.new).search("a")
  end

  test "search merges remote-only cards not in the catalog" do
    remote = [{ "id" => 999, "name" => "Blue-Eyes White Dragon", "type" => "Normal Monster", "frameType" => "normal", "archetype" => "Blue-Eyes" }]
    results = CardProvisioner.new(client: StubClient.new(remote: remote)).search("blue")
    bew = results.find { |s| s.ygo_id == 999 }
    assert_not_nil bew
    assert_not bew.in_catalog?
  end

  test "ensure returns an existing card without ingesting" do
    card = CardProvisioner.new(client: StubClient.new).ensure(@ash.ygo_id)
    assert_equal @ash, card
  end

  test "ensure ingests an unknown card from the client" do
    remote = [{ "id" => 999, "name" => "Blue-Eyes White Dragon", "type" => "Normal Monster", "frameType" => "normal" }]
    card = CardProvisioner.new(client: StubClient.new(remote: remote)).ensure(999)
    assert_equal "Blue-Eyes White Dragon", card.name
    assert Card.exists?(ygo_id: 999)
  end
end
