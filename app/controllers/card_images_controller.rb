# Serves self-hosted card art. The 408 committed meta images are served straight
# from disk by the static middleware; this controller only handles MISSES - cards
# the user added on demand whose art was never committed (or was wiped when the
# ephemeral filesystem reset on a redeploy). It downloads the art from YGOPRODeck
# once (compliant self-hosting, not hotlinking) and caches it for next time.
class CardImagesController < ApplicationController
  # How long to remember that an id has no art, so a broken passcode (or one
  # YGOPRODeck doesn't carry) is not re-downloaded on every page render.
  MISS_TTL = 6.hours

  def show
    id = params[:ygo_image_id].to_i
    path = Rails.root.join("public", "card_images", "#{id}.jpg")

    download_missing(id, path) if !File.exist?(path) && !recent_miss?(id)

    if File.exist?(path)
      response.set_header("Cache-Control", "public, max-age=31536000, immutable")
      send_file path, type: "image/jpeg", disposition: "inline"
    else
      Rails.cache.write(miss_key(id), true, expires_in: MISS_TTL)
      # Let the browser/CDN cache the miss too so it stops re-requesting a
      # known-bad id (much shorter TTL than a real hit, in case art lands later).
      response.set_header("Cache-Control", "public, max-age=3600")
      head :not_found
    end
  end

  private

  CDN_SMALL = "https://images.ygoprodeck.com/images/cards_small".freeze

  def miss_key(id) = "card_image_miss:#{id}"
  def recent_miss?(id) = Rails.cache.read(miss_key(id)).present?

  def download_missing(id, _path)
    image = CardImage.find_by(ygo_image_id: id)
    url =
      if image&.image_url.present?
        image.image_url.sub("/cards/", "/cards_small/")
      else
        # A card the user surfaced via the full-database search but never
        # ingested: the default artwork id equals the card passcode, so we can
        # self-host it on demand (still no hotlinking - we cache and serve it).
        "#{CDN_SMALL}/#{id}.jpg"
      end

    CardImageDownloader.new(throttle: 0).call(url, id)
  rescue => e
    Rails.logger.warn("[CardImagesController] download #{id} failed: #{e.message}")
  end
end
