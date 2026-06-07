module Api
  module V1
    class CardsController < BaseController
      # GET /api/v1/cards
      # Filters: ?q= (name), ?archetype=, ?banlist_format=md&banlist_status=forbidden
      def index
        scope = Card.all
        scope = scope.search_name(params[:q]) if params[:q].present?
        scope = scope.by_archetype(params[:archetype]) if params[:archetype].present?
        scope = filter_by_banlist(scope)
        scope = scope.order(:name)

        cards, meta = paginate(scope)

        if stale?(etag: [cards.cache_key_with_version, meta], public: true)
          render json: {
            data: cards.map { |c| CardSerializer.new(c) },
            meta: meta
          }
        end
      end

      # GET /api/v1/cards/:id  (accepts our id or the YGOPRODeck ygo_id)
      def show
        card = find_card!
        if stale?(card, public: true)
          render json: { data: CardSerializer.new(card, detailed: true) }
        end
      end

      # GET /api/v1/cards/:id/printings
      # Variant drill-down. Filters: ?rarity_tier= ?edition= ?language= ?foil=true ?promo=true
      def printings
        card = find_card!
        scope = card.printings
                    .by_rarity_tier(params[:rarity_tier])
                    .by_edition(params[:edition])
                    .by_language(params[:language])
        scope = scope.foils if truthy?(params[:foil])
        scope = scope.promos if truthy?(params[:promo])
        scope = scope.order(:set_code, :set_rarity)

        render json: {
          data: scope.map { |p| PrintingSerializer.new(p) },
          meta: { card_id: card.id, ygo_id: card.ygo_id, total: scope.size }
        }
      end

      # GET /api/v1/cards/:id/audit
      # Catalog-accuracy view: source provenance, cross-source conflicts, and
      # derived data-quality flags (banlist divergence, price spread).
      def audit
        card = find_card!
        render json: { data: {
          id: card.id,
          ygo_id: card.ygo_id,
          name: card.name,
          sources: card.reconciled_sources,
          provenance: card.source_provenance,
          conflicts: card.data_conflicts,
          banlist_divergence: banlist_divergence(card),
          price_outlier: price_outlier?(card)
        } }
      end

      private

      def find_card!
        Card.find_by(id: params[:id]) || Card.find_by!(ygo_id: params[:id])
      end

      def truthy?(value)
        %w[1 true yes].include?(value.to_s.downcase)
      end

      def filter_by_banlist(scope)
        return scope if params[:banlist_format].blank? || params[:banlist_status].blank?

        scope.joins(:banlist_entries).where(
          banlist_entries: { format: params[:banlist_format], status: params[:banlist_status] }
        ).distinct
      end

      # The headline reconciliation example: a card can be legal in one format and
      # restricted in another (Maxx "C": forbidden in TCG, limited in Master Duel).
      def banlist_divergence(card)
        tcg = card.banlist_status("tcg")
        md = card.banlist_status("md")
        { tcg: tcg, md: md, divergent: tcg != md }
      end

      # Flags a suspicious vendor-price spread (max more than 3x the min).
      def price_outlier?(card)
        amounts = card.prices.filter_map(&:amount)
        return false if amounts.size < 2

        amounts.max > amounts.min * 3
      end
    end
  end
end
