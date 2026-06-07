class AddImpactToCounterRecommendations < ActiveRecord::Migration[8.1]
  def change
    add_column :counter_recommendations, :impact, :string
  end
end
