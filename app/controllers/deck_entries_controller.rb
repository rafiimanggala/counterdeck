# Add / adjust / remove cards in a user deck. The builder UI is optimistic and
# client-side, so these endpoints just PERSIST and return light JSON - they never
# recompute matchups (that is a separate, lazily-loaded endpoint). Adding a card
# resolves it through CardProvisioner, ingesting it from YGOPRODeck on demand if
# it is not already in the local catalog.
class DeckEntriesController < ApplicationController
  before_action :set_deck
  before_action :require_owner

  # Idempotent upsert keyed by (card, zone):
  #   no quantity param -> increment by one (capped at 3)
  #   quantity = N       -> set to N (0 removes the card)
  def create
    card = CardProvisioner.new.ensure(params[:ygo_id])
    return render(json: { ok: false, error: "Card not found or YGOPRODeck unavailable." }, status: :unprocessable_entity) if card.nil?

    zone = normalize_zone(params[:zone], card)
    entry = @deck.deck_entries.find_or_initialize_by(card_id: card.id, zone: zone)

    if params.key?(:quantity)
      qty = params[:quantity].to_i
      if qty < 1
        entry.destroy unless entry.new_record?
        return render json: { ok: true, ygo_id: card.ygo_id, zone: zone, quantity: 0 }
      end
      entry.quantity = [qty, 3].min
    else
      entry.quantity = entry.new_record? ? 1 : [entry.quantity + 1, 3].min
    end

    entry.position ||= @deck.deck_entries.size
    entry.save!
    render json: entry_json(entry, card)
  end

  def update
    entry = @deck.deck_entries.find(params[:id])
    qty = params[:quantity].to_i
    if qty < 1
      entry.destroy
      render json: { ok: true, id: entry.id, quantity: 0 }
    else
      entry.update(quantity: [qty, 3].min)
      render json: { ok: true, id: entry.id, quantity: entry.quantity }
    end
  end

  def destroy
    entry = @deck.deck_entries.find(params[:id])
    entry.destroy
    render json: { ok: true, id: entry.id, quantity: 0 }
  end

  private

  def set_deck
    @deck = UserDeck.find_by!(slug: params[:user_deck_slug])
  end

  def require_owner
    head :forbidden unless @deck.owned_by?(builder_token)
  end

  # Extra-deck monster frame types belong in the extra zone unless told otherwise.
  EXTRA_FRAMES = %w[fusion synchro xyz link].freeze
  def normalize_zone(zone, card)
    zone = zone.to_s.downcase
    return zone if UserDeck::ZONES.include?(zone)

    EXTRA_FRAMES.any? { |f| card.frame_type.to_s.include?(f) } ? "extra" : "main"
  end

  def entry_json(entry, card)
    {
      ok: true,
      id: entry.id,
      card_id: card.id,
      ygo_id: card.ygo_id,
      zone: entry.zone,
      quantity: entry.quantity,
      name: card.name,
      kind: card.card_kind,
      img: card.primary_image&.ygo_image_id
    }
  end
end
