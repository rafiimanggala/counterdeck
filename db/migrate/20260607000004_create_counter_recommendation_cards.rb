# A counter recommendation can name more than one card ("Effect Veiler /
# Infinite Impermanence", "Kaijus / Lava Golem"). This join lets a single rec
# carry the art of every card it names, while the rec's own `card_id` stays the
# primary card used for scoring and banlist.
class CreateCounterRecommendationCards < ActiveRecord::Migration[8.1]
  def change
    create_table :counter_recommendation_cards do |t|
      t.references :counter_recommendation, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :counter_recommendation_cards, %i[counter_recommendation_id card_id],
              unique: true, name: "index_crc_on_rec_and_card"
  end
end
