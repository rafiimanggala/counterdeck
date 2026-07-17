class BanlistEntry < ApplicationRecord
  FORBIDDEN = "forbidden".freeze
  LIMITED = "limited".freeze
  SEMI_LIMITED = "semi_limited".freeze
  UNLIMITED = "unlimited".freeze
  STATUSES = [ FORBIDDEN, LIMITED, SEMI_LIMITED, UNLIMITED ].freeze

  TCG = "tcg".freeze
  OCG = "ocg".freeze
  GOAT = "goat".freeze
  MD = "md".freeze # Master Duel (derived, not in YGOPRODeck API)
  FORMATS = [ TCG, OCG, GOAT, MD ].freeze

  belongs_to :card

  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }
  validates :format, uniqueness: { scope: :card_id }

  scope :for_format, ->(fmt) { where(format: fmt) }
  scope :restricted, -> { where.not(status: UNLIMITED) }

  # Maps a YGOPRODeck ban string ("Banned"/"Limited"/"Semi-Limited") to our status.
  def self.normalize_status(raw)
    case raw.to_s.downcase
    when "banned", "forbidden" then FORBIDDEN
    when "limited" then LIMITED
    when "semi-limited", "semi_limited" then SEMI_LIMITED
    else UNLIMITED
    end
  end
end
