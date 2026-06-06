namespace :cards do
  # Staple disruption cards every counter sheet references. Exact names so the
  # catalog is populated with the pieces players actually hold/break with.
  STAPLE_CARDS = [
    "Ash Blossom & Joyous Spring",
    "Maxx \"C\"",
    "Nibiru, the Primal Being",
    "Droll & Lock Bird",
    "Effect Veiler",
    "Infinite Impermanence",
    "Ghost Ogre & Snow Rabbit",
    "Ghost Belle & Haunted Mansion",
    "D.D. Crow",
    "Called by the Grave",
    "Crossout Designator",
    "Triple Tactics Talent",
    "Lightning Storm",
    "Evenly Matched",
    "Harpie's Feather Duster",
    "Forbidden Droplet",
    "Super Polymerization",
    "Dark Ruler No More",
    "Cosmic Cyclone",
    "Dimension Shifter",
    "Gameciel, the Sea Turtle Kaiju",
    "Kurikara Divincarnate"
  ].freeze

  # Real, currently-relevant archetypes available in YGOPRODeck.
  META_ARCHETYPES = [
    "Sky Striker", "Branded", "Labrynth", "Snake-Eye", "Fiendsmith",
    "Tearlaments", "Yummy", "Blue-Eyes", "Mitsurugi"
  ].freeze

  desc "Ingest cards by filter, e.g. rake 'cards:ingest[archetype,Blue-Eyes]'"
  task :ingest, %i[filter_type value] => :environment do |_t, args|
    filter = { args[:filter_type] => args[:value] }
    result = IngestCardsJob.new.perform(filter)
    puts "#{filter.inspect} -> #{result.to_h}"
  end

  desc "Ingest staple hand traps / board breakers by name"
  task ingest_staples: :environment do
    client = YgoprodeckClient.new
    ingestor = CardIngestor.new
    STAPLE_CARDS.each do |name|
      cards = client.cards(name: name)
      if cards.empty?
        puts "  MISS  #{name}"
      else
        ingestor.call(cards)
        puts "  ok    #{name}"
      end
    end
    puts "staples done"
  end

  desc "Ingest all meta archetypes"
  task ingest_archetypes: :environment do
    META_ARCHETYPES.each do |archetype|
      result = IngestCardsJob.new.perform({ "archetype" => archetype })
      puts "  #{archetype} -> #{result.to_h}"
    end
    puts "archetypes done"
  end

  desc "Ingest everything CounterDeck needs (staples + meta archetypes)"
  task ingest_meta: %i[environment ingest_staples ingest_archetypes] do
    puts "Catalog: #{Card.count} cards, #{Printing.count} printings, #{Price.count} prices, #{BanlistEntry.count} banlist entries"
  end

  desc "Import the derived Master Duel banlist and report TCG divergences"
  task import_md_banlist: :environment do
    result = MasterDuelBanlist.new.import
    puts "MD banlist imported: #{result.imported}, unmatched: #{result.unmatched.size}"
    puts "Divergences vs TCG (#{result.divergences.size}):"
    result.divergences.each do |d|
      puts "  #{d.card.name.ljust(40)} TCG=#{d.tcg_status.ljust(13)} MD=#{d.md_status}"
    end
  end
end
