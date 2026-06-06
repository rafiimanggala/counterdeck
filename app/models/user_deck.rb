require "securerandom"

# A deck the visitor builds themselves (the reverse of the meta decks): given the
# cards they run, CounterDeck shows which of their cards already counter each meta
# deck. Ownership is anonymous - tied to a signed cookie token, not a user account.
class UserDeck < ApplicationRecord
  ZONES = %w[main extra side].freeze

  has_many :deck_entries, -> { order(:position, :id) }, dependent: :destroy
  has_many :cards, through: :deck_entries

  validates :name, presence: true, length: { maximum: 80 }
  validates :slug, presence: true, uniqueness: true
  validates :owner_token, presence: true

  before_validation :ensure_slug

  def to_param = slug

  def entries_in(zone) = deck_entries.select { |e| e.zone == zone }
  def main_entries  = entries_in("main")
  def extra_entries = entries_in("extra")
  def side_entries  = entries_in("side")

  def card_count(zone = nil)
    (zone ? entries_in(zone) : deck_entries).sum(&:quantity)
  end

  # Set of catalog card ids in this deck (any zone) - drives the matchup view.
  def card_id_set
    @card_id_set ||= deck_entries.map(&:card_id).to_set
  end

  def owned_by?(token)
    token.present? && owner_token == token
  end

  private

  def ensure_slug
    return if slug.present?

    base = name.to_s.parameterize.presence || "deck"
    candidate = base
    suffix = 0
    candidate = "#{base}-#{suffix += 1}" while UserDeck.where(slug: candidate).where.not(id: id).exists?
    self.slug = candidate
  end
end
