# Idempotent seed: import the drafted meta-deck counter sheets.
# Assumes the card catalog is already populated (rake cards:ingest_meta) and the
# Master Duel banlist imported (rake cards:import_md_banlist), but works without
# them too (counter cards just stay as free text until linked).
result = CounterSeedImporter.new.import
puts "Seeded decks: #{result.decks}"
puts "Counter recommendations: #{result.recommendations} (linked to catalog: #{result.linked}, free-text: #{result.unlinked})"
