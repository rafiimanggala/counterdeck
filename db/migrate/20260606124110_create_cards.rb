class CreateCards < ActiveRecord::Migration[8.1]
  def change
    create_table :cards do |t|
      t.bigint :ygo_id
      t.string :name
      t.string :frame_type
      t.string :card_kind
      t.string :ygo_attribute
      t.string :race
      t.integer :atk
      t.integer :defense
      t.integer :level
      t.integer :scale
      t.integer :linkval
      t.string :archetype
      t.text :card_text
      t.string :image_filename

      t.timestamps
    end
    add_index :cards, :ygo_id, unique: true
    add_index :cards, :name
    add_index :cards, :archetype
  end
end
