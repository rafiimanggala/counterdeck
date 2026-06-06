Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ---- Public counter cheat-sheet (Hotwire) ----
  root "decks#index"
  resources :decks, only: %i[index show], param: :slug
  resource :scan, only: %i[show create], controller: "scan"

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
      resources :cards, only: %i[index show]
      resources :decks, only: %i[index show], param: :slug
    end
  end
end
