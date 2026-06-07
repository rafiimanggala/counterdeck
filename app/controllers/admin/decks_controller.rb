module Admin
  class DecksController < ApplicationController
    layout "admin"

    before_action :set_deck, only: %i[edit update destroy verify]

    def index
      @decks = Deck.order(updated_at: :desc)
    end

    def new
      @deck = Deck.new(status: "draft")
      seed_blank_rows(@deck)
    end

    def create
      @deck = Deck.new(deck_params)
      if @deck.save
        redirect_to edit_admin_deck_path(@deck), notice: "Deck created."
      else
        seed_blank_rows(@deck)
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @deck.update(deck_params)
        redirect_to edit_admin_deck_path(@deck), notice: "Saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @deck.destroy
      redirect_to admin_decks_path, notice: "Deck deleted."
    end

    def verify
      @deck.update(status: "verified")
      redirect_to admin_decks_path, notice: "#{@deck.name} marked verified."
    end

    private

    def set_deck
      @deck = Deck.find_by!(slug: params[:id])
    end

    def seed_blank_rows(deck)
      3.times { deck.counter_recommendations.build(category: CounterRecommendation::HAND_TRAP) }
    end

    def deck_params
      params.require(:deck).permit(
        :name, :archetype, :tier, :formats, :game_plan,
        :going_first_vs_second, :beginner_explanation, :confidence, :status,
        :interruption_points_text,
        counter_recommendations_attributes: %i[id category card_name note timing impact position _destroy]
      )
    end
  end
end
