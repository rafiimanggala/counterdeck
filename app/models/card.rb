class Card < ApplicationRecord
  has_many :printings, dependent: :destroy
  has_many :prices, dependent: :destroy
  has_many :card_images, dependent: :destroy
  has_many :banlist_entries, dependent: :destroy
  has_many :counter_recommendations, dependent: :nullify

  validates :ygo_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :by_archetype, ->(archetype) { where(archetype: archetype) if archetype.present? }
  scope :search_name, ->(q) { where("name ILIKE ?", "%#{sanitize_sql_like(q)}%") if q.present? }

  # Current ban status for a given format ("tcg", "ocg", "goat", "md").
  # Returns "unlimited" when no restriction is recorded.
  def banlist_status(format)
    banlist_entries.find { |e| e.format == format.to_s }&.status || BanlistEntry::UNLIMITED
  end

  def primary_image
    card_images.min_by(&:id)
  end

  def lowest_price
    prices.filter_map(&:amount).min
  end
end
