# Autocomplete for the deck builder: searches the local catalog and the full
# YGOPRODeck database, returning lightweight JSON the search Stimulus controller
# renders into a results dropdown. Cards are only ingested when actually added.
class CardsController < ApplicationController
  def search
    suggestions = CardProvisioner.new.search(params[:q])
    render json: suggestions.map { |s|
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
end
