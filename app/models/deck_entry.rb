# One card slot in a user-built deck. Quantity is capped at 3 (the Yu-Gi-Oh
# copy limit); zone is main / extra / side.
class DeckEntry < ApplicationRecord
  belongs_to :user_deck
  belongs_to :card

  validates :zone, inclusion: { in: UserDeck::ZONES }
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 3 }
  validates :card_id, uniqueness: { scope: %i[user_deck_id zone] }

  delegate :name, :primary_image, :archetype, :card_kind, to: :card, prefix: false, allow_nil: true
end
