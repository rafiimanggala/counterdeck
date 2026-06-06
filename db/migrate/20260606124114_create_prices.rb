class CreatePrices < ActiveRecord::Migration[8.1]
  def change
    create_table :prices do |t|
      t.references :card, null: false, foreign_key: true
      t.string :source, null: false
      t.decimal :amount, precision: 12, scale: 2
      t.string :currency
      t.datetime :captured_at

      t.timestamps
    end
    add_index :prices, [:card_id, :source], unique: true
  end
end
