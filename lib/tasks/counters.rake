namespace :counters do
  # The `impact` column is a MANUAL OVERRIDE only: nil means "auto" and the tier
  # is derived live by CounterImpact (cheap - a few hundred string scans). This
  # task just previews what the heuristic produces, so the scoring can be tuned
  # and spot-checked without writing anything.
  desc "Preview the CounterImpact heuristic distribution (read-only, no writes)"
  task impact_preview: :environment do
    recs = CounterRecommendation.where(category: %w[hand_trap board_breaker]).includes(:card)
    tally = Hash.new(0)
    recs.each { |r| tally[CounterImpact.tier(r, ignore_override: true)] += 1 }

    total = tally.values.sum
    puts "CounterImpact heuristic over #{total} recommendations:"
    %i[high medium low].each do |t|
      n = tally[t]
      puts "  #{t.to_s.ljust(7)}: #{n.to_s.rjust(3)} (#{total.zero? ? 0 : (100.0 * n / total).round}%)"
    end
  end

  # Validate the frozen card-art links (db/seeds/counter_card_links.json) against
  # the drafted descriptors and the live catalog. Read-only: flags stale ygo_ids,
  # ids whose art is missing, and descriptors that resolve to no card art at all
  # (candidates for a new link entry). Run after editing either seed file.
  desc "Validate counter_card_links.json: stale ids, missing art, unresolved descriptors"
  task check_links: :environment do
    data = JSON.parse(File.read(CounterSeedImporter::SEED_PATH))
    links = JSON.parse(File.read(CounterSeedImporter::LINKS_PATH))

    all_ids = links.values.flat_map(&:values).flatten.uniq
    stale = all_ids.reject { |id| Card.exists?(ygo_id: id) }
    no_art = all_ids.select { |id| Card.exists?(ygo_id: id) && !Card.find_by(ygo_id: id).primary_image&.ygo_image_id }

    importer = CounterSeedImporter.new
    unresolved = []
    Array(data["counters"]).each do |entry|
      slug = entry["deck_name"].to_s.parameterize
      %w[key_cards hand_traps board_breakers].each do |sec|
        Array(entry[sec]).each do |item|
          raw = item["card"].to_s
          next if raw.blank?

          unresolved << "#{slug} :: #{raw}" if importer.send(:resolve_cards, slug, raw).empty?
        end
      end
    end

    puts "Link entries: #{all_ids.size} distinct cards across #{links.size} decks"
    puts "Stale ygo_ids (not in catalog): #{stale.empty? ? 'none' : stale.inspect}"
    puts "Ids without art:               #{no_art.empty? ? 'none' : no_art.inspect}"
    puts "Descriptors with no card art (#{unresolved.size}):"
    unresolved.each { |u| puts "  #{u}" }
    puts "  none (every descriptor resolves)" if unresolved.empty?
  end
end
