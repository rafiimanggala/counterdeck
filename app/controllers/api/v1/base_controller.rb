module Api
  module V1
    class BaseController < ActionController::API
      MAX_PER_PAGE = 100
      DEFAULT_PER_PAGE = 25

      # Self-contained store so rate limiting works in every environment
      # regardless of the app-wide cache configuration.
      RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

      rate_limit to: 100, within: 1.minute, store: RATE_LIMIT_STORE,
                 with: -> { render json: { error: "rate_limited", message: "Too many requests, slow down." }, status: :too_many_requests }

      rescue_from ActiveRecord::RecordNotFound, with: :not_found

      private

      def paginate(relation)
        page = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].to_i
        per_page = DEFAULT_PER_PAGE if per_page <= 0
        per_page = [ per_page, MAX_PER_PAGE ].min

        total = relation.count
        records = relation.limit(per_page).offset((page - 1) * per_page)
        [ records, pagination_meta(total, page, per_page) ]
      end

      def pagination_meta(total, page, per_page)
        {
          total: total,
          page: page,
          per_page: per_page,
          total_pages: (total.to_f / per_page).ceil
        }
      end

      def not_found(error)
        render json: { error: "not_found", message: error.message }, status: :not_found
      end
    end
  end
end
