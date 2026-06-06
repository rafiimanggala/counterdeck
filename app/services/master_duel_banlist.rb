# Derives the Master Duel banlist that the YGOPRODeck API does NOT provide.
#
# YGOPRODeck only exposes ban_tcg / ban_ocg / ban_goat. Master Duel runs a
# separate Forbidden & Limited list, so we maintain a hand-curated snapshot in
# db/seeds/md_banlist.json (sourced from Konami's in-client list) and import it
# as BanlistEntry rows with format="md". After import we reconcile against the
# TCG status to surface DIVERGENCES (the headline data-correctness feature).
class MasterDuelBanlist
  SEED_PATH = Rails.root.join("db", "seeds", "md_banlist.json")

  Divergence = Struct.new(:card, :tcg_status, :md_status, keyword_init: true)
  ImportResult = Struct.new(:imported, :unmatched, :divergences, keyword_init: true)

  def initialize(path: SEED_PATH, logger: Rails.logger)
    @path = path
    @logger = logger
  end

  def import
    data = JSON.parse(File.read(@path))
    source = data["source"]
    captured_at = parse_date(data["captured_on"])

    imported = 0
    unmatched = []

    Array(data["entries"]).each do |entry|
      card = Card.find_by(name: entry["name"])
      unless card
        unmatched << entry["name"]
        next
      end

      status = entry["status"].to_s
      next unless BanlistEntry::STATUSES.include?(status)

      record = card.banlist_entries.find_or_initialize_by(format: BanlistEntry::MD)
      record.status = status
      record.source = source
      record.captured_at = captured_at
      record.save!
      imported += 1
    end

    @logger.warn("[MasterDuelBanlist] unmatched names: #{unmatched.join(', ')}") if unmatched.any?
    ImportResult.new(imported: imported, unmatched: unmatched, divergences: divergences)
  end

  # Cards whose Master Duel status differs from their TCG status.
  # This is the data-correctness signal a naive single-banlist build would miss.
  def divergences
    Card.joins(:banlist_entries)
        .where(banlist_entries: { format: BanlistEntry::MD })
        .distinct
        .filter_map do |card|
      md = card.banlist_status(BanlistEntry::MD)
      tcg = card.banlist_status(BanlistEntry::TCG)
      next if md == tcg

      Divergence.new(card: card, tcg_status: tcg, md_status: md)
    end
  end

  private

  def parse_date(str)
    Date.parse(str.to_s).to_time
  rescue ArgumentError, TypeError
    Time.current
  end
end
