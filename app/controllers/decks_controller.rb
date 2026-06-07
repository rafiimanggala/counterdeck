# Public-facing counter cheat-sheet.
class DecksController < ApplicationController
  VALID_FORMATS = %w[md tcg].freeze

  def index
    @decks = Deck.includes(counter_recommendations: { card: :card_images })
    @decks = @decks.search(params[:q]) if params[:q].present?
    @decks = @decks.by_format(params[:format]) if params[:format].present?
    @decks = @decks.order(:name)
    @query = params[:q]
  end

  def show
    @deck = Deck.includes(counter_recommendations: { card: [:card_images, :banlist_entries], art_cards: :card_images }).find_by!(slug: params[:slug])
    # `fmt`, not `format`: the latter is Rails' reserved MIME param and 406s on ".md".
    @format = VALID_FORMATS.include?(params[:fmt]) ? params[:fmt] : "md"
  end
end
