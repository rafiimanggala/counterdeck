class CreateBanlistEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :banlist_entries do |t|
      t.references :card, null: false, foreign_key: true
      t.string :format, null: false
      t.string :status, null: false
      t.string :source
      t.datetime :captured_at

      t.timestamps
    end
    add_index :banlist_entries, [:card_id, :format], unique: true
  end
end
