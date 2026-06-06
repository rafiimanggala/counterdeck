class CreateCounterRecommendations < ActiveRecord::Migration[8.1]
  def change
    create_table :counter_recommendations do |t|
      t.references :deck, null: false, foreign_key: true
      t.references :card, null: true, foreign_key: true
      t.string :card_name
      t.string :category, null: false
      t.text :note
      t.string :timing
      t.integer :position, default: 0, null: false

      t.timestamps
    end
    add_index :counter_recommendations, [:deck_id, :category, :position]
  end
end
