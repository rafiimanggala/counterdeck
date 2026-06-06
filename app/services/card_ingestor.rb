# Normalizes raw YGOPRODeck card hashes into our relational schema:
#   Card -> many Printings (variants), many Prices (vendors), many CardImages,
#   plus BanlistEntry rows for tcg/ocg/goat (Master Duel is derived elsewhere).
#
# Idempotent: re-running upserts by natural keys (ygo_id, set_code+rarity, vendor)
# so a re-sync never duplicates rows.
class CardIngestor
  Result = Struct.new(:cards, :printings, :prices, :images, :banlist, keyword_init: true)

  CURRENCY_BY_SOURCE = {
    "cardmarket" => "EUR",
    "tcgplayer" => "USD",
    "ebay" => "USD",
    "amazon" => "USD",
    "coolstuffinc" => "USD"
  }.freeze

  def initialize(downloader: nil, logger: Rails.logger)
    @downloader = downloader
    @logger = logger
    @result = Result.new(cards: 0, printings: 0, prices: 0, images: 0, banlist: 0)
  end

  # api_cards: Array of card Hashes (string keys) from YgoprodeckClient#cards.
  def call(api_cards)
    Array(api_cards).each do |data|
      ActiveRecord::Base.transaction { ingest_one(data) }
    rescue => e
      @logger.error("[CardIngestor] failed for ygo_id=#{data['id']} (#{data['name']}): #{e.class} #{e.message}")
    end
    @result
  end

  private

  def ingest_one(data)
    card = Card.find_or_initialize_by(ygo_id: data["id"])
    card.assign_attributes(
      name: data["name"],
      frame_type: data["frameType"],
      card_kind: data["type"],
      ygo_attribute: data["attribute"],
      race: data["race"],
      atk: data["atk"],
      defense: data["def"],
      level: data["level"],
      scale: data["scale"],
      linkval: data["linkval"],
      archetype: data["archetype"],
      card_text: data["desc"]
    )
    card.save!
    @result.cards += 1

    sync_printings(card, data["card_sets"])
    sync_prices(card, data["card_prices"])
    sync_images(card, data["card_images"])
    sync_banlist(card, data["banlist_info"])
    card
  end

  def sync_printings(card, sets)
    Array(sets).each do |set|
      printing = card.printings.find_or_initialize_by(
        set_code: set["set_code"],
        set_rarity: set["set_rarity"]
      )
      next if printing.set_code.blank?

      printing.set_name = set["set_name"]
      printing.set_rarity_code = set["set_rarity_code"]
      printing.set_price = parse_amount(set["set_price"])
      printing.save!
      @result.printings += 1
    end
  end

  def sync_prices(card, price_blocks)
    block = Array(price_blocks).first || {}
    Price::SOURCES.each do |source|
      raw = block["#{source}_price"]
      next if raw.blank?

      amount = parse_amount(raw)
      next if amount.nil? || amount.zero?

      price = card.prices.find_or_initialize_by(source: source)
      price.amount = amount
      price.currency = CURRENCY_BY_SOURCE[source]
      price.captured_at = Time.current
      price.save!
      @result.prices += 1
    end
  end

  def sync_images(card, images)
    Array(images).each_with_index do |img, index|
      image = card.card_images.find_or_initialize_by(ygo_image_id: img["id"])
      image.image_url = img["image_url"]
      image.is_alt_art = index.positive?
      image.save!
      @result.images += 1
      @downloader&.call(img["image_url"], img["id"])
    end
  end

  def sync_banlist(card, info)
    return if info.blank?

    { BanlistEntry::TCG => info["ban_tcg"],
      BanlistEntry::OCG => info["ban_ocg"],
      BanlistEntry::GOAT => info["ban_goat"] }.each do |format, raw|
      next if raw.blank?

      entry = card.banlist_entries.find_or_initialize_by(format: format)
      entry.status = BanlistEntry.normalize_status(raw)
      entry.source = "ygoprodeck"
      entry.captured_at = Time.current
      entry.save!
      @result.banlist += 1
    end
  end

  def parse_amount(raw)
    return nil if raw.blank?

    value = raw.to_s.delete(",").to_d
    value.zero? ? nil : value
  rescue ArgumentError
    nil
  end
end
