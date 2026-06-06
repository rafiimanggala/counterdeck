# Add / adjust / remove cards in a user deck. Adding a card resolves it through
# CardProvisioner, ingesting it from YGOPRODeck on demand if it is not already in
# the local catalog. Responds with Turbo Streams so the builder updates in place.
class DeckEntriesController < ApplicationController
  before_action :set_deck
  before_action :require_owner

  def create
    card = CardProvisioner.new.ensure(params[:ygo_id])
    if card.nil?
      return respond_error("Couldn't find that card on YGOPRODeck.")
    end

    zone = normalize_zone(params[:zone], card)
    entry = @deck.deck_entries.find_or_initialize_by(card_id: card.id, zone: zone)
    if entry.new_record?
      entry.position = @deck.deck_entries.size
      entry.quantity = 1
    else
      entry.quantity = [entry.quantity + 1, 3].min
    end
    entry.save!
    rebuild_and_render
  end

  def update
    entry = @deck.deck_entries.find(params[:id])
    qty = params[:quantity].to_i
    if qty <= 0
      entry.destroy
    else
      entry.update(quantity: [qty, 3].min)
    end
    rebuild_and_render
  end

  def destroy
    @deck.deck_entries.find(params[:id]).destroy
    rebuild_and_render
  end

  private

  def set_deck
    @deck = UserDeck.includes(deck_entries: { card: :card_images }).find_by!(slug: params[:user_deck_slug])
  end

  def require_owner
    head :forbidden unless @deck.owned_by?(builder_token)
  end

  # Extra-deck monster frame types belong in the extra zone unless told otherwise.
  EXTRA_FRAMES = %w[fusion synchro xyz link].freeze
  def normalize_zone(zone, card)
    return zone if UserDeck::ZONES.include?(zone)

    EXTRA_FRAMES.any? { |f| card.frame_type.to_s.include?(f) } ? "extra" : "main"
  end

  def rebuild_and_render
    @deck.reload
    @editable = true
    @matchups = DeckMatchup.new(@deck).matchups
    @related = RelatedCards.new(@deck).suggestions
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @deck }
    end
  end

  def respond_error(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("builder_flash", %(<p class="rounded-lg border border-rose-700 bg-rose-950 px-3 py-2 text-sm text-rose-300">#{ERB::Util.html_escape(message)}</p>).html_safe) }
      format.html { redirect_to @deck, alert: message }
    end
  end
end
