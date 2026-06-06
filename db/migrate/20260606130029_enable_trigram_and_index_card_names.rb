class EnableTrigramAndIndexCardNames < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    # GIN trigram index makes fuzzy card-name matching (OCR scan) fast.
    add_index :cards, :name, using: :gin, opclass: :gin_trgm_ops,
              name: "index_cards_on_name_trgm", if_not_exists: true
  end
end
