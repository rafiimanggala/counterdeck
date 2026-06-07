class AddVariantFieldsToPrintings < ActiveRecord::Migration[8.1]
  # Models the physical product reality the source feed flattens away: the same
  # card name ships as many printings that differ by rarity/finish, edition,
  # promo status, and language. The natural key widens to include edition so a
  # 1st-edition and an unlimited print of the same set+rarity are distinct rows.
  def up
    change_table :printings, bulk: true do |t|
      t.string  :edition, null: false, default: "unlimited"
      t.boolean :foil, null: false, default: false
      t.boolean :promo, null: false, default: false
      t.string  :language, null: false, default: "en"
      t.string  :rarity_tier
      t.jsonb   :variant_meta, null: false, default: {}
    end

    add_index :printings, %i[card_id rarity_tier], name: "index_printings_on_card_and_rarity_tier"
    add_index :printings, :promo, where: "promo", name: "index_printings_on_promo"

    remove_index :printings, name: "index_printings_on_card_set_rarity"
    add_index :printings, %i[card_id set_code set_rarity edition],
              unique: true, name: "index_printings_on_card_set_rarity_edition"
  end

  def down
    remove_index :printings, name: "index_printings_on_card_set_rarity_edition"
    add_index :printings, %i[card_id set_code set_rarity],
              unique: true, name: "index_printings_on_card_set_rarity"
    remove_index :printings, name: "index_printings_on_promo"
    remove_index :printings, name: "index_printings_on_card_and_rarity_tier"

    change_table :printings, bulk: true do |t|
      t.remove :edition, :foil, :promo, :language, :rarity_tier, :variant_meta
    end
  end
end
