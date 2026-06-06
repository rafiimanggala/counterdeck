class CounterRecommendation < ApplicationRecord
  KEY_CARD = "key_card".freeze
  HAND_TRAP = "hand_trap".freeze
  BOARD_BREAKER = "board_breaker".freeze
  CATEGORIES = [KEY_CARD, HAND_TRAP, BOARD_BREAKER].freeze

  belongs_to :deck
  belongs_to :card, optional: true

  validates :category, inclusion: { in: CATEGORIES }
  validate :must_name_a_card

  before_validation :autolink_card

  scope :in_category, ->(cat) { where(category: cat).order(:position) }

  # Prefer the linked catalog card name; fall back to the free-text name
  # (lets Rafii input a counter before the card is ingested).
  def display_name
    card&.name.presence || card_name
  end

  private

  # Lets Rafii just type a card name; we link it to the catalog automatically
  # when there's a match. Unmatched names stay as free text (still valid).
  def autolink_card
    return if card_id.present? || card_name.blank?

    match = Card.find_by(name: card_name) || Card.where("name ILIKE ?", card_name).first
    self.card = match if match
  end

  def must_name_a_card
    if card_id.blank? && card_name.blank?
      errors.add(:base, "must reference a card or provide a card name")
    end
  end
end
