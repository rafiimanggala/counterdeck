class CreateUserDecks < ActiveRecord::Migration[8.1]
  def change
    create_table :user_decks do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :owner_token, null: false
      t.timestamps
    end
    add_index :user_decks, :slug, unique: true
    add_index :user_decks, :owner_token

    create_table :deck_entries do |t|
      t.references :user_deck, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: true
      t.string :zone, null: false, default: "main"
      t.integer :quantity, null: false, default: 1
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :deck_entries, %i[user_deck_id card_id zone], unique: true, name: "index_deck_entries_unique_card_per_zone"
  end
end
