module Api
  module V1
    class DecksController < BaseController
      # GET /api/v1/decks  Filters: ?q=, ?format=, ?tier=, ?status=verified
      def index
        scope = Deck.all
        scope = scope.search(params[:q]) if params[:q].present?
        scope = scope.by_format(params[:format]) if params[:format].present?
        scope = scope.where(tier: params[:tier]) if params[:tier].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.order(:name)

        decks, meta = paginate(scope)

        render json: {
          data: decks.map { |d| DeckSerializer.new(d) },
          meta: meta
        }
      end

      # GET /api/v1/decks/:slug  -> full counter sheet
      def show
        deck = Deck.includes(counter_recommendations: :card).find_by!(slug: params[:slug])
        render json: { data: DeckSerializer.new(deck, detailed: true) }
      end
    end
  end
end
