# Real Battle: pit one of the visitor's own decks against a single current meta
# deck and show a tailored, highly visual counter read (readiness, the enemy's
# threats, and which of the user's cards answer them). Read-only.
class BattlesController < ApplicationController
  FORMATS = %w[tcg md].freeze

  def show
    @my_decks = UserDeck.where(owner_token: builder_token)
                        .includes(deck_entries: { card: :card_images })
                        .order(updated_at: :desc)
    @my_deck = @my_decks.find_by(slug: params[:mine]) || @my_decks.first

    @format = FORMATS.include?(params[:banlist]) ? params[:banlist] : "tcg"

    @meta_decks = Deck.verified
                      .includes(counter_recommendations: { card: :card_images })
                      .order(:name)
    @enemy = @meta_decks.find_by(slug: params[:vs])

    @matchup = DeckMatchup.new(@my_deck, format: @format).matchup_for(@enemy) if @my_deck && @enemy
  end
end
