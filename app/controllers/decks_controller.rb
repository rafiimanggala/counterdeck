# Public-facing counter cheat-sheet.
class DecksController < ApplicationController
  VALID_FORMATS = %w[md tcg].freeze

  def index
    @decks = Deck.all
    @decks = @decks.search(params[:q]) if params[:q].present?
    @decks = @decks.by_format(params[:format]) if params[:format].present?
    @decks = @decks.order(:name)
    @query = params[:q]
  end

  def show
    @deck = Deck.includes(counter_recommendations: :card).find_by!(slug: params[:slug])
    @format = VALID_FORMATS.include?(params[:format]) ? params[:format] : "md"
  end
end
