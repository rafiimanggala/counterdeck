# Idempotent seed: import the drafted meta-deck counter sheets. Card art is
# attached from the frozen db/seeds/counter_card_links.json (verify it with
# `rake counters:check_links`). Assumes the card catalog is already populated
# (rake cards:ingest_meta) and the Master Duel banlist imported
# (rake cards:import_md_banlist), but works without them too (counters whose
# catalog cards are missing simply stay as free text until the catalog fills in).
result = CounterSeedImporter.new.import
puts "Seeded decks: #{result.decks}"
puts "Counter recommendations: #{result.recommendations} (linked to catalog: #{result.linked}, free-text: #{result.unlinked})"
