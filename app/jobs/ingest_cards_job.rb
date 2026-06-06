# Fetches cards from YGOPRODeck matching a filter and ingests them.
# filter examples: { "archetype" => "Blue-Eyes" }, { "fname" => "Ash" }
class IngestCardsJob < ApplicationJob
  queue_as :default

  def perform(filter, download_images: false)
    cards = YgoprodeckClient.new.cards(**filter.symbolize_keys)
    downloader = download_images ? CardImageDownloader.new : nil
    result = CardIngestor.new(downloader: downloader).call(cards)
    Rails.logger.info("[IngestCardsJob] #{filter.inspect} -> #{result.to_h}")
    result
  end
end
