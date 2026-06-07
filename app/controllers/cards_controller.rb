# Card data for the deck builder.
#   index   -> slim JSON of the WHOLE local catalog, loaded once so search/filter
#              is instant and client-side (the Master Duel model: no server hit
#              per keystroke). Cards outside the catalog use #search on demand.
#   search  -> autocomplete that also reaches the full YGOPRODeck DB (cached).
#   show    -> full card detail (effect text + stats), rendered into a modal.
class CardsController < ApplicationController
  def index
    cards = Rails.cache.fetch("cards_catalog_index/v2", expires_in: 1.hour) do
      Card.includes(:card_images, :banlist_entries).order(:name).map { |c| index_row(c) }
    end
    response.set_header("Cache-Control", "public, max-age=300")
    render json: cards
  end

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

  def show
    card = CardProvisioner.new.ensure(params[:ygo_id])
    return head :not_found if card.nil?

    render partial: "cards/detail", locals: { card: card, builder: params[:builder].present? }, layout: false
  end

  private

  def index_row(card)
    img = card.card_images.min_by(&:id)
    row = {
      ygo_id: card.ygo_id,
      name: card.name,
      kind: card.card_kind,
      frame: card.frame_type,
      attr: card.ygo_attribute,
      race: card.race,
      level: card.level,
      atk: card.atk,
      def: card.defense,
      archetype: card.archetype,
      img: img&.ygo_image_id
    }
    ban = banlist_map(card)
    row[:ban] = ban if ban.any?
    row
  end

  # Restricted statuses per format the builder enforces (tcg, md). Unlimited
  # cards are omitted so the index JSON stays tiny (only ~35 of 210 cards carry
  # any restriction); the client treats a missing entry as unlimited.
  def banlist_map(card)
    card.banlist_entries.each_with_object({}) do |entry, map|
      next if entry.status == BanlistEntry::UNLIMITED
      next unless [BanlistEntry::TCG, BanlistEntry::MD].include?(entry.format)

      map[entry.format] = entry.status
    end
  end
end
