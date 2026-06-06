# Serves self-hosted card art. The 408 committed meta images are served straight
# from disk by the static middleware; this controller only handles MISSES - cards
# the user added on demand whose art was never committed (or was wiped when the
# ephemeral filesystem reset on a redeploy). It downloads the art from YGOPRODeck
# once (compliant self-hosting, not hotlinking) and caches it for next time.
class CardImagesController < ApplicationController
  def show
    id = params[:ygo_image_id].to_i
    path = Rails.root.join("public", "card_images", "#{id}.jpg")

    download_missing(id, path) unless File.exist?(path)

    if File.exist?(path)
      response.set_header("Cache-Control", "public, max-age=31536000, immutable")
      send_file path, type: "image/jpeg", disposition: "inline"
    else
      head :not_found
    end
  end

  private

  def download_missing(id, _path)
    image = CardImage.find_by(ygo_image_id: id)
    return if image&.image_url.blank?

    small = image.image_url.sub("/cards/", "/cards_small/")
    CardImageDownloader.new(throttle: 0).call(small, id)
  rescue => e
    Rails.logger.warn("[CardImagesController] download #{id} failed: #{e.message}")
  end
end
