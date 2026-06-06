module Admin
  # Lightweight JSON card-name search powering the input autocomplete datalist.
  class CardLookupsController < ApplicationController
    def index
      names = Card.search_name(params[:q]).order(:name).limit(20).pluck(:name)
      render json: names
    end
  end
end
