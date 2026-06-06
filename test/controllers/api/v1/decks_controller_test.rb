require "test_helper"

module Api
  module V1
    class DecksControllerTest < ActionDispatch::IntegrationTest
      setup do
        @deck = Deck.create!(name: "Kewl Tune", tier: "Tier 1", formats: "TCG, Master Duel", status: "verified")
        @deck.counter_recommendations.create!(category: "hand_trap", card_name: "Ash Blossom & Joyous Spring", note: "stops searches")
        @deck.counter_recommendations.create!(category: "board_breaker", card_name: "Lightning Storm")
      end

      test "index lists decks" do
        get "/api/v1/decks"
        assert_response :success
        body = JSON.parse(response.body)
        assert_equal 1, body["meta"]["total"]
        assert_equal "Kewl Tune", body["data"].first["name"]
      end

      test "show returns grouped counters" do
        get "/api/v1/decks/#{@deck.slug}"
        assert_response :success
        data = JSON.parse(response.body)["data"]
        assert_equal 1, data["hand_traps"].size
        assert_equal 1, data["board_breakers"].size
        assert_equal "Ash Blossom & Joyous Spring", data["hand_traps"].first["card"]
      end

      test "show 404 for unknown slug" do
        get "/api/v1/decks/does-not-exist"
        assert_response :not_found
      end
    end
  end
end
