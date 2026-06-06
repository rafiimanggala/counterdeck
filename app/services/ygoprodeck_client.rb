require "net/http"
require "json"
require "uri"

# Thin client for the YGOPRODeck API v7 (https://ygoprodeck.com/api-guide/).
#
# Notes from the API guide we deliberately respect:
#   - Rate limit is 20 requests/second; exceeding it blocks you for 1 hour.
#   - Card images must NOT be hotlinked; download and self-host instead.
#   - The banlist only exposes ban_tcg / ban_ocg / ban_goat. There is NO
#     Master Duel banlist field (handled separately, see MasterDuelBanlist).
class YgoprodeckClient
  BASE_URL = "https://db.ygoprodeck.com/api/v7"
  CARDINFO = "#{BASE_URL}/cardinfo.php".freeze

  class Error < StandardError; end
  class RateLimited < Error; end
  class NotFound < Error; end

  def initialize(logger: Rails.logger, open_timeout: 5, read_timeout: 20)
    @logger = logger
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  # Fetch cards from cardinfo.php. Pass any supported filter, e.g.
  #   cards(archetype: "Blue-Eyes")
  #   cards(fname: "Ash")
  #   cards(name: "Ash Blossom & Joyous Spring")
  # Returns an Array of card Hashes (string keys). Empty array when none match.
  def cards(**params)
    body = get(CARDINFO, params)
    Array(body["data"])
  rescue NotFound
    []
  end

  private

  def get(url, params)
    uri = URI(url)
    uri.query = URI.encode_www_form(params) if params.present?

    response = with_retries do
      http_get(uri)
    end

    case response.code.to_i
    when 200
      JSON.parse(response.body)
    when 400
      # YGOPRODeck returns 400 with an error body when no cards match a filter.
      raise NotFound, safe_error(response.body)
    when 429
      raise RateLimited, "YGOPRODeck rate limit hit (20 req/s)"
    else
      raise Error, "YGOPRODeck HTTP #{response.code}: #{response.body.to_s[0, 200]}"
    end
  end

  def http_get(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "CounterDeck/1.0 (+https://github.com/rafiimanggala/counterdeck)"
    http.request(request)
  end

  # One retry with backoff on transient network / rate-limit errors.
  def with_retries(attempts: 2)
    tries = 0
    begin
      tries += 1
      yield
    rescue RateLimited, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
      if tries <= attempts
        sleep(2 * tries)
        retry
      end
      raise
    end
  end

  def safe_error(body)
    JSON.parse(body)["error"]
  rescue JSON::ParserError
    body.to_s[0, 200]
  end
end
