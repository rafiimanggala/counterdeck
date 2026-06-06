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
        card = Card.find_by(id: params[:id]) || Card.find_by!(ygo_id: params[:id])
        if stale?(card, public: true)
          render json: { data: CardSerializer.new(card, detailed: true) }
        end
      end

      private

      def filter_by_banlist(scope)
        return scope if params[:banlist_format].blank? || params[:banlist_status].blank?

        scope.joins(:banlist_entries).where(
          banlist_entries: { format: params[:banlist_format], status: params[:banlist_status] }
        ).distinct
      end
    end
  end
end
