class Deck < ApplicationRecord
  TIERS = ["Tier 0", "Tier 1", "Tier 2", "Tier 3", "Rogue"].freeze
  STATUSES = %w[draft verified].freeze
  CONFIDENCE = %w[high medium low].freeze

  has_many :counter_recommendations, -> { order(:position) }, dependent: :destroy
  accepts_nested_attributes_for :counter_recommendations, allow_destroy: true, reject_if: :all_blank

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :ensure_slug

  scope :verified, -> { where(status: "verified") }
  scope :by_format, ->(fmt) { where("formats ILIKE ?", "%#{sanitize_sql_like(fmt)}%") if fmt.present? }
  scope :search, ->(q) { where("name ILIKE :q OR archetype ILIKE :q", q: "%#{sanitize_sql_like(q)}%") if q.present? }

  def to_param = slug

  def key_cards = counter_recommendations.select { |r| r.category == CounterRecommendation::KEY_CARD }
  def hand_traps = counter_recommendations.select { |r| r.category == CounterRecommendation::HAND_TRAP }
  def board_breakers = counter_recommendations.select { |r| r.category == CounterRecommendation::BOARD_BREAKER }

  def interruption_points
    Array(super)
  end

  def format_list
    formats.to_s.split(/[,\/]/).map(&:strip).reject(&:blank?)
  end

  private

  def ensure_slug
    self.slug = name.to_s.parameterize if slug.blank? && name.present?
  end
end
