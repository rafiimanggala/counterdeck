require "net/http"
require "uri"

# Downloads and self-hosts card art under public/card_images/<id>.jpg.
# YGOPRODeck forbids hotlinking (IP-blacklist enforced), so we cache locally
# and serve from our own origin. Skips files that already exist (idempotent).
class CardImageDownloader
  DIR = Rails.root.join("public", "card_images")

  def initialize(logger: Rails.logger, throttle: 0.1)
    @logger = logger
    @throttle = throttle
    FileUtils.mkdir_p(DIR)
  end

  def call(url, ygo_image_id)
    return if url.blank? || ygo_image_id.blank?

    path = DIR.join("#{ygo_image_id}.jpg")
    return path if File.exist?(path)

    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) do |http|
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "CounterDeck/1.0"
      response = http.request(request)
      if response.code.to_i == 200
        File.binwrite(path, response.body)
      else
        @logger.warn("[CardImageDownloader] HTTP #{response.code} for #{url}")
        return nil
      end
    end
    sleep(@throttle) if @throttle.positive?
    path
  rescue => e
    @logger.warn("[CardImageDownloader] failed #{url}: #{e.class} #{e.message}")
    nil
  end
end
