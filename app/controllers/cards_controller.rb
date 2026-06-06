# Autocomplete for the deck builder: searches the local catalog and the full
# YGOPRODeck database, returning lightweight JSON the search Stimulus controller
# renders into a results dropdown. Cards are only ingested when actually added.
class CardsController < ApplicationController
  def search
    q = params[:q].to_s.strip.downcase
    # Cache identical queries so search-as-you-type doesn't hammer YGOPRODeck
    # (20 req/s hard limit, then a 1-hour IP block) and repeat lookups are free.
    data = Rails.cache.fetch("cards_search/#{q}", expires_in: 6.hours) do
      CardProvisioner.new.search(q).map { |s|
        {
          ygo_id: s.ygo_id,
          name: s.name,
          kind: s.card_kind,
          archetype: s.archetype,
          in_catalog: s.in_catalog?,
          image: s.card&.primary_image&.ygo_image_id
        }
      }
    end
    render json: data
  end
end
