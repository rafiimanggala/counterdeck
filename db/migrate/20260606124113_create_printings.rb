class CreatePrintings < ActiveRecord::Migration[8.1]
  def change
    create_table :printings do |t|
      t.references :card, null: false, foreign_key: true
      t.string :set_name
      t.string :set_code
      t.string :set_rarity
      t.string :set_rarity_code
      t.decimal :set_price, precision: 12, scale: 2

      t.timestamps
    end
    add_index :printings, :set_code
    add_index :printings, [ :card_id, :set_code, :set_rarity ], unique: true, name: "index_printings_on_card_set_rarity"
  end
end
