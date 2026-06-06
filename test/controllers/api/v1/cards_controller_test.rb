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
    end
  end
end
