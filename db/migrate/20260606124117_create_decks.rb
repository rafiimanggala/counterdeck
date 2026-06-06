class CreateDecks < ActiveRecord::Migration[8.1]
  def change
    create_table :decks do |t|
      t.string :name
      t.string :slug
      t.string :archetype
      t.string :tier
      t.string :formats
      t.text :game_plan
      t.text :going_first_vs_second
      t.text :beginner_explanation
      t.jsonb :interruption_points, default: [], null: false
      t.string :status, null: false, default: "draft"
      t.string :confidence
      t.text :source_note

      t.timestamps
    end
    add_index :decks, :slug, unique: true
  end
end
