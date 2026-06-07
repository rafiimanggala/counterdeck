Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ---- Public counter cheat-sheet (Hotwire) ----
  root "decks#index"
  resources :decks, only: %i[index show], param: :slug
  resource :scan, only: %i[show create], controller: "scan"

  # ---- Build your own deck (reverse counter-match) ----
  resources :user_decks, param: :slug, path: "my-decks" do
    member { get :matchups }
    resources :deck_entries, only: %i[create update destroy]
  end
  # ---- Real Battle: your deck vs one meta deck, head to head ----
  resource :battle, only: :show, controller: "battles"

  get "cards/search", to: "cards#search", as: :cards_search
  get "cards/index", to: "cards#index", as: :cards_index
  get "cards/:ygo_id", to: "cards#show", as: :card, constraints: { ygo_id: /\d+/ }

  # Lazy fallback for card art not on disk (static middleware serves the hits).
  get "card_images/:ygo_image_id", to: "card_images#show", constraints: { ygo_image_id: /\d+/ }

  # ---- Admin (Rafii inputs counters here) ----
  namespace :admin do
    root "decks#index"
    resources :decks do
      member { patch :verify }
    end
    resources :card_lookups, only: :index
    get "data_quality", to: "data_quality#index"
  end

  # ---- Versioned JSON API ----
  namespace :api do
    namespace :v1 do
      resources :cards, only: %i[index show] do
        member do
          get :printings
          get :audit
        end
      end
      resources :decks, only: %i[index show], param: :slug
    end
  end
end
