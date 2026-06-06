class Printing < ApplicationRecord
  belongs_to :card

  validates :set_code, presence: true

  scope :by_rarity, ->(rarity) { where(set_rarity: rarity) if rarity.present? }
end
