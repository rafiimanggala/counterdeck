# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_07_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "banlist_entries", force: :cascade do |t|
    t.datetime "captured_at"
    t.bigint "card_id", null: false
    t.datetime "created_at", null: false
    t.string "format", null: false
    t.string "source"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id", "format"], name: "index_banlist_entries_on_card_id_and_format", unique: true
    t.index ["card_id"], name: "index_banlist_entries_on_card_id"
  end

  create_table "card_images", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.datetime "created_at", null: false
    t.string "image_url"
    t.boolean "is_alt_art", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "ygo_image_id"
    t.index ["card_id"], name: "index_card_images_on_card_id"
    t.index ["ygo_image_id"], name: "index_card_images_on_ygo_image_id"
  end

  create_table "cards", force: :cascade do |t|
    t.string "archetype"
    t.integer "atk"
    t.string "card_kind"
    t.text "card_text"
    t.datetime "created_at", null: false
    t.integer "defense"
    t.string "frame_type"
    t.string "image_filename"
    t.integer "level"
    t.integer "linkval"
    t.string "name"
    t.string "race"
    t.integer "scale"
    t.datetime "updated_at", null: false
    t.string "ygo_attribute"
    t.bigint "ygo_id"
    t.index ["archetype"], name: "index_cards_on_archetype"
    t.index ["name"], name: "index_cards_on_name"
    t.index ["name"], name: "index_cards_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["ygo_id"], name: "index_cards_on_ygo_id", unique: true
  end

  create_table "counter_recommendations", force: :cascade do |t|
    t.bigint "card_id"
    t.string "card_name"
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.bigint "deck_id", null: false
    t.text "note"
    t.integer "position", default: 0, null: false
    t.string "timing"
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_counter_recommendations_on_card_id"
    t.index ["deck_id", "category", "position"], name: "idx_on_deck_id_category_position_1731a97d03"
    t.index ["deck_id"], name: "index_counter_recommendations_on_deck_id"
  end

  create_table "deck_entries", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_deck_id", null: false
    t.string "zone", default: "main", null: false
    t.index ["card_id"], name: "index_deck_entries_on_card_id"
    t.index ["user_deck_id", "card_id", "zone"], name: "index_deck_entries_unique_card_per_zone", unique: true
    t.index ["user_deck_id"], name: "index_deck_entries_on_user_deck_id"
  end

  create_table "decks", force: :cascade do |t|
    t.string "archetype"
    t.text "beginner_explanation"
    t.string "confidence"
    t.datetime "created_at", null: false
    t.string "formats"
    t.text "game_plan"
    t.text "going_first_vs_second"
    t.jsonb "interruption_points", default: [], null: false
    t.string "name"
    t.string "slug"
    t.text "source_note"
    t.string "status", default: "draft", null: false
    t.string "tier"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_decks_on_slug", unique: true
  end

  create_table "prices", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2
    t.datetime "captured_at"
    t.bigint "card_id", null: false
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id", "source"], name: "index_prices_on_card_id_and_source", unique: true
    t.index ["card_id"], name: "index_prices_on_card_id"
  end

  create_table "printings", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.datetime "created_at", null: false
    t.string "set_code"
    t.string "set_name"
    t.decimal "set_price", precision: 12, scale: 2
    t.string "set_rarity"
    t.string "set_rarity_code"
    t.datetime "updated_at", null: false
    t.index ["card_id", "set_code", "set_rarity"], name: "index_printings_on_card_set_rarity", unique: true
    t.index ["card_id"], name: "index_printings_on_card_id"
    t.index ["set_code"], name: "index_printings_on_set_code"
  end

  create_table "user_decks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "owner_token", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_token"], name: "index_user_decks_on_owner_token"
    t.index ["slug"], name: "index_user_decks_on_slug", unique: true
  end

  add_foreign_key "banlist_entries", "cards"
  add_foreign_key "card_images", "cards"
  add_foreign_key "counter_recommendations", "cards"
  add_foreign_key "counter_recommendations", "decks"
  add_foreign_key "deck_entries", "cards"
  add_foreign_key "deck_entries", "user_decks"
  add_foreign_key "prices", "cards"
  add_foreign_key "printings", "cards"
end
