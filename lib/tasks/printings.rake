namespace :printings do
  desc "Backfill normalized variant fields (rarity_tier/foil/promo) on existing printings"
  task backfill_variants: :environment do
    updated = 0
    Printing.find_each do |printing|
      variant = Printing.classify(
        set_rarity: printing.set_rarity, set_code: printing.set_code, set_name: printing.set_name
      )
      printing.update_columns(
        rarity_tier: variant[:rarity_tier],
        foil: variant[:foil],
        promo: variant[:promo]
      )
      updated += 1
    end
    puts "Backfilled #{updated} printings with variant fields."
  end
end
