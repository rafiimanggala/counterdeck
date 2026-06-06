class Price < ApplicationRecord
  SOURCES = %w[cardmarket tcgplayer ebay amazon coolstuffinc].freeze

  belongs_to :card

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :source, uniqueness: { scope: :card_id }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :for_source, ->(src) { where(source: src) }
end
