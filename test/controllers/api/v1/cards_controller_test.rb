require "test_helper"

module Api
  module V1
    class CardsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @ash = Card.create!(ygo_id: 14558127, name: "Ash Blossom & Joyous Spring", card_kind: "Effect Monster")
        @ash.banlist_entries.create!(format: "md", status: "limited")
      end

      test "index returns paginated json envelope" do
        get "/api/v1/cards", params: { per_page: 5 }
        assert_response :success
        body = JSON.parse(response.body)
        assert_kind_of Array, body["data"]
        assert_equal 1, body["meta"]["total"]
        assert_equal 5, body["meta"]["per_page"]
      end

      test "index filters by name" do
        Card.create!(ygo_id: 999, name: "Blue-Eyes White Dragon")
        get "/api/v1/cards", params: { q: "blue-eyes" }
        body = JSON.parse(response.body)
        assert_equal 1, body["meta"]["total"]
        assert_equal "Blue-Eyes White Dragon", body["data"].first["name"]
      end

      test "show returns detail with format-aware banlist" do
        get "/api/v1/cards/#{@ash.ygo_id}"
        assert_response :success
        data = JSON.parse(response.body)["data"]
        assert_equal "limited", data["banlist"]["md"]
        assert data.key?("printings")
      end

      test "show returns 404 for unknown id" do
        get "/api/v1/cards/123456789"
        assert_response :not_found
      end

      test "printings endpoint returns every variant with normalized fields" do
        @ash.printings.create!(set_code: "MAMA-EN030", set_rarity: "Ultra Rare",
                               rarity_tier: "ultra", foil: true, edition: "unlimited")
        @ash.printings.create!(set_code: "DUDE-EN015", set_rarity: "Ultra Rare",
                               rarity_tier: "ultra", foil: true, edition: "1st")
        @ash.printings.create!(set_code: "SDFC-EN001", set_rarity: "Common",
                               rarity_tier: "standard", foil: false, edition: "unlimited")

        get "/api/v1/cards/#{@ash.ygo_id}/printings"
        assert_response :success
        body = JSON.parse(response.body)
        assert_equal 3, body["meta"]["total"]
        assert body["data"].all? { |p| p.key?("rarity_tier") && p.key?("edition") && p.key?("foil") }
      end

      test "printings endpoint filters by foil and rarity_tier" do
        @ash.printings.create!(set_code: "MAMA-EN030", set_rarity: "Ultra Rare", rarity_tier: "ultra", foil: true)
        @ash.printings.create!(set_code: "SDFC-EN001", set_rarity: "Common", rarity_tier: "standard", foil: false)

        get "/api/v1/cards/#{@ash.ygo_id}/printings", params: { foil: "true" }
        assert_equal 1, JSON.parse(response.body)["meta"]["total"]

        get "/api/v1/cards/#{@ash.ygo_id}/printings", params: { rarity_tier: "standard" }
        body = JSON.parse(response.body)
        assert_equal 1, body["meta"]["total"]
        assert_equal "Common", body["data"].first["rarity"]
      end

      test "audit endpoint exposes banlist divergence and reconciliation metadata" do
        @ash.banlist_entries.create!(format: "tcg", status: "forbidden")
        @ash.update!(metadata: {
          "sources" => %w[ygoprodeck manual],
          "provenance" => { "atk" => "manual" },
          "conflicts" => [{ "field" => "atk", "chosen" => 600, "chosen_source" => "manual", "losing_source" => "ygoprodeck" }]
        })

        get "/api/v1/cards/#{@ash.ygo_id}/audit"
        assert_response :success
        data = JSON.parse(response.body)["data"]
        assert data["banlist_divergence"]["divergent"], "tcg forbidden vs md limited should diverge"
        assert_equal "forbidden", data["banlist_divergence"]["tcg"]
        assert_includes data["sources"], "manual"
        assert_equal "atk", data["conflicts"].first["field"]
      end
    end
  end
end
