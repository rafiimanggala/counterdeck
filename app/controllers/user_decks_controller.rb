# The visitor's own deck builder. Decks are owned by an anonymous cookie token;
# anyone with the slug can view a deck, only the owner can edit it.
class UserDecksController < ApplicationController
  before_action :set_deck, only: %i[show edit update destroy matchups]
  before_action :require_owner, only: %i[edit update destroy]

  def index
    @decks = UserDeck.where(owner_token: builder_token).order(updated_at: :desc)
  end

  def new
    @deck = UserDeck.new
  end

  def create
    @deck = UserDeck.new(deck_params.merge(owner_token: builder_token))
    if @deck.save
      redirect_to @deck, notice: "Deck created. Start adding cards."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @editable = @deck.owned_by?(builder_token)
  end

  # Loaded lazily (and refreshed after edits) so the expensive reverse
  # counter-match never blocks an add. Renders just the matchups frame.
  def matchups
    # This renders a bare turbo-frame fragment (layout: false). Opened directly in
    # a browser it would show unstyled (no Tailwind), so bounce a non-frame request
    # back to the styled deck page where the frame loads in context.
    return redirect_to(user_deck_path(@deck)) unless turbo_frame_request?

    # The banlist format rides on the "banlist" param (NOT "format": Rails reads
    # params[:format] as the response MIME type). formats: :html is belt-and-braces
    # so a stale client still sending ?format=md can never 500 with MissingTemplate.
    @format = params[:banlist].to_s.presence_in(BanlistEntry::FORMATS)
    @matchups = DeckMatchup.new(@deck, format: @format).matchups
    render :matchups, layout: false, formats: :html
  end

  def edit; end

  def update
    if @deck.update(deck_params)
      redirect_to @deck, notice: "Deck renamed."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @deck.destroy
    redirect_to user_decks_path, notice: "Deck deleted."
  end

  private

  def set_deck
    @deck = UserDeck.includes(deck_entries: { card: :card_images }).find_by!(slug: params[:slug])
  end

  def require_owner
    redirect_to(@deck, alert: "That isn't your deck.") unless @deck.owned_by?(builder_token)
  end

  def deck_params
    params.require(:user_deck).permit(:name)
  end
end
