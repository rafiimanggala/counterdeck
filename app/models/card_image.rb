class CardImage < ApplicationRecord
  belongs_to :card

  # Local self-hosted path (YGOPRODeck forbids hotlinking; see README).
  def local_path
    "/card_images/#{ygo_image_id}.jpg"
  end
end
