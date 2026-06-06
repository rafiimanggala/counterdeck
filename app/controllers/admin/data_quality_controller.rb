module Admin
  # Catalog-accuracy dashboard: the data-correctness story made visible.
  class DataQualityController < ApplicationController
    layout "admin"

    def index
      @md_divergences = MasterDuelBanlist.new.divergences
      @unlinked = CounterRecommendation.where(card_id: nil).includes(:deck).order("decks.name")
      @draft_decks = Deck.where(status: "draft").order(:name)
      @stats = {
        cards: Card.count,
        printings: Printing.count,
        prices: Price.count,
        decks: Deck.count,
        verified_decks: Deck.verified.count,
        recommendations: CounterRecommendation.count,
        md_banlist: BanlistEntry.for_format("md").count
      }
    end
  end
end
