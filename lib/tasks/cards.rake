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
    "Kurikara Divincarnate",
    # Standalone removal / floodgates / boss monsters that counter sheets cite by name.
    "Lava Golem",
    "Twin Twisters",
    "Mystical Space Typhoon",
    "Transaction Rollback",
    "Imperial Iron Wall",
    "Dimensional Fissure",
    "Macro Cosmos",
    "Mulcharmy Fuwalos",
    "Mulcharmy Purulia",
    "Diabellstar the Black Witch",
    "Aluber the Jester of Despia",
    "Dogmatika Fleurdelis, the Knighted",
    "Baronne de Montmorency",
    "Herald of the Arc Light",
    "Thunder Dragon Colossus",
    "Thunder King, the Lightningstrike Kaiju",
    "Radian, the Multidimensional Kaiju",
    "Mulcharmy Meowls"
  ].freeze

  # Real, currently-relevant archetypes available in YGOPRODeck. Covers every
  # deck a counter sheet references so the deck's own cards land in the catalog.
  META_ARCHETYPES = [
    "Sky Striker", "Branded", "Labrynth", "Snake-Eye", "Fiendsmith",
    "Tearlaments", "Yummy", "Blue-Eyes", "Mitsurugi",
    "Maliss", "Vanquish Soul", "Dracotail", "Magnet Warrior", "K9",
    "Mulcharmy", "Centur-Ion", "Ryzeal", "Memento", "Voiceless Voice"
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

  desc "Ingest every distinct card NAME referenced by the counter sheets (fills gaps archetypes miss)"
  task ingest_counter_cards: :environment do
    data = JSON.parse(File.read(Rails.root.join("db", "seeds", "meta_counters.json")))
    raw_names = []
    Array(data["counters"]).each do |e|
      %w[key_cards hand_traps board_breakers].each do |sec|
        Array(e[sec]).each { |c| raw_names << c["card"] }
      end
    end

    cleaned = raw_names.flat_map do |raw|
      base = raw.to_s.gsub(/\s*\([^)]*\)\s*/, " ").strip
      next [] if base.match?(CounterSeedImporter::DESCRIPTIVE)
      base.split(%r{\s*/\s*}).map(&:strip)
    end.reject(&:blank?)
    cleaned = cleaned.map { |n| CounterSeedImporter::ALIASES[n.downcase.strip] || n }.uniq

    client = YgoprodeckClient.new
    ingestor = CardIngestor.new
    added = 0
    miss = []
    cleaned.each do |name|
      next if name.length < 3 || name.match?(CounterSeedImporter::DESCRIPTIVE)
      next if Card.where("lower(name) = ?", name.downcase).exists?

      cards = client.cards(name: name)
      cards = client.cards(fname: name) if cards.empty?
      # Broad fname can over-match; keep only cards clearly related to the query.
      if cards.size > 3
        key = name.downcase
        cards = cards.select { |c| c["name"].to_s.downcase.include?(key) || key.include?(c["name"].to_s.downcase.split(/[,(]/).first.to_s.strip) }
      end
      if cards.empty?
        miss << name
      else
        ingestor.call(cards)
        added += cards.size
        print "."
      end
      sleep 0.06 # respect 20 req/s
    end
    puts ""
    puts "counter cards: +#{added} card rows ingested, #{miss.size} unresolved"
    puts "unresolved (likely role text / nicknames): #{miss.first(40).join(' | ')}" if miss.any?
  end

  desc "Ingest everything CounterDeck needs (staples + meta archetypes + counter card names)"
  task ingest_meta: %i[environment ingest_staples ingest_archetypes ingest_counter_cards] do
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
