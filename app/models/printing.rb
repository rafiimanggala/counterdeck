# A single physical printing (variant) of a card. The source feed (YGOPRODeck)
# gives free-text rarity strings and rarely an edition, so this model is the one
# place that maps that messy input onto a stable, queryable variant shape:
# rarity_tier (normalized finish), edition, foil, promo, language.
class Printing < ApplicationRecord
  EDITIONS = %w[unlimited 1st limited].freeze

  # Normalized finish/rarity buckets, most-valuable first. Derived from the raw
  # set_rarity string which is inconsistent across sets and languages.
  RARITY_TIERS = %w[
    standard rare super ultra secret ultimate ghost
    starlight collectors quarter_century prismatic other
  ].freeze

  # Conservative set-code prefixes that denote tournament/promo distributions.
  PROMO_CODE_PREFIXES = %w[OP YCSW WCPS JUMP MOV CT SBAD PR].freeze

  belongs_to :card

  validates :set_code, presence: true
  validates :language, presence: true
  validates :edition, inclusion: { in: EDITIONS }
  validates :rarity_tier, inclusion: { in: RARITY_TIERS }, allow_nil: true
  validates :set_code, uniqueness: {
    scope: %i[card_id set_rarity edition],
    message: "already recorded for this card, rarity, and edition"
  }

  scope :by_rarity, ->(rarity) { where(set_rarity: rarity) if rarity.present? }
  scope :by_rarity_tier, ->(tier) { where(rarity_tier: tier) if tier.present? }
  scope :by_edition, ->(edition) { where(edition: edition) if edition.present? }
  scope :by_language, ->(lang) { where(language: lang) if lang.present? }
  scope :foils, -> { where(foil: true) }
  scope :promos, -> { where(promo: true) }

  # Map a raw YGOPRODeck card_set hash onto normalized variant fields. Pure and
  # side-effect free so it can be reused by the ingestor and by backfills.
  def self.classify(set_rarity:, set_code: nil, set_name: nil)
    tier = rarity_tier_for(set_rarity)
    {
      rarity_tier: tier,
      foil: foil_for(tier),
      promo: promo_for(set_code, set_rarity),
      edition: edition_for(set_name)
    }
  end

  def self.rarity_tier_for(set_rarity)
    r = set_rarity.to_s.downcase
    return "standard" if r.blank? || r.include?("common")
    return "quarter_century" if r.include?("quarter century") || r.include?("25th")
    return "starlight" if r.include?("starlight")
    return "ghost" if r.include?("ghost")
    return "ultimate" if r.include?("ultimate")
    return "collectors" if r.include?("collector")
    return "prismatic" if r.include?("prismatic")
    return "secret" if r.include?("secret")
    return "ultra" if r.include?("ultra")
    return "super" if r.include?("super")
    return "rare" if r.include?("rare")

    "other"
  end

  # Commons and plain Rares are non-foil; every higher tier carries a foil.
  def self.foil_for(tier)
    !%w[standard rare].include?(tier)
  end

  def self.promo_for(set_code, set_rarity)
    return true if set_rarity.to_s.downcase.include?("promo")

    code = set_code.to_s.upcase
    PROMO_CODE_PREFIXES.any? { |prefix| code.start_with?(prefix) }
  end

  def self.edition_for(set_name)
    set_name.to_s.downcase.include?("1st") ? "1st" : "unlimited"
  end
end
