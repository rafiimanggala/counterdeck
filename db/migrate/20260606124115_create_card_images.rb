class CreateCardImages < ActiveRecord::Migration[8.1]
  def change
    create_table :card_images do |t|
      t.references :card, null: false, foreign_key: true
      t.bigint :ygo_image_id
      t.string :image_url
      t.boolean :is_alt_art, default: false, null: false

      t.timestamps
    end
    add_index :card_images, :ygo_image_id
  end
end
