# Deterministic High / Medium / Low impact tier for a counter recommendation.
# The tier answers "how much does this card actually hurt that deck" so the UI
# can show a 3-segment severity bar instead of a wall of prose.
#
# Precedence:
#   1. an explicit `impact` override on the record (Rafii's hand-correction) wins
#   2. a card forbidden in the active format is demoted to :low (never advise a
#      banned card as a hard out)
#   3. otherwise a keyword + card heuristic scores the recommendation
#
# Pure (no DB writes). Used by the backfill rake task and by the matchup view.
class CounterImpact
  TIERS  = %w[high medium low].freeze
  WEIGHT = { high: 3, medium: 2, low: 1 }.freeze

  LABEL = { high: "Stops their combo", medium: "Slows them down", low: "Situational" }.freeze

  # Universally strong, deck-agnostic outs - always start a tier above baseline.
  ALLOWLIST = [
    'Maxx "C"', "Ash Blossom", "Droll & Lock Bird", "Nibiru", "Effect Veiler",
    "Infinite Impermanence", "Ghost Ogre", "Forbidden Droplet", "Super Polymerization",
    "Lightning Storm", "Evenly Matched", "Harpie's Feather Duster", "Kaiju",
    "Lava Golem", "Dark Ruler No More", "Dimension Shifter"
  ].freeze

  UP_KEYWORDS = [
    "best single", "best out", "best counter", "best hand trap", "best board breaker",
    "best disruption", "single best", "premier", "go-to", "shuts off", "shuts down",
    "turns off", "stop the combo", "can stop", "single-card answer", "reliable",
    "guaranteed", "cleanly", "ignoring its negate", "must short-stop", "outright",
    "core to", "shut down", "completely stops", "hard stops", "blowout", "back-breaking"
  ].freeze

  DOWN_KEYWORDS = [
    "play around", "plays around", "played around", "dodge", "chain-block",
    "loses value", "situational", "niche", " soft ", " weak ", "baits",
    "not a guaranteed", "requirement", "requires", "only clears", "symmetric",
    "at best", "marginal", "less impactful", "lower impact", "easily played around"
  ].freeze

  class << self
    def label(tier) = LABEL[tier.to_sym]
    def weight(tier) = WEIGHT[tier.to_sym] || 0

    # tier(rec, format:) -> :high | :medium | :low
    # `ignore_override: true` returns the pure heuristic (used by the backfill).
    def tier(rec, format: nil, ignore_override: false)
      unless ignore_override
        override = rec.impact.presence
        return override.to_sym if override && TIERS.include?(override)
      end

      return :low if format && rec.card && rec.card.banlist_status(format) == BanlistEntry::FORBIDDEN

      bucket(score(rec))
    end

    private

    # Category (board breakers swing harder than hand traps) gives a small base,
    # the allowlist a small prior, and the deck-specific note does most of the
    # work. Tuned so a curated list spreads roughly high / medium / low rather
    # than collapsing to "everything is high".
    def score(rec)
      base = { CounterRecommendation::BOARD_BREAKER => 2, CounterRecommendation::HAND_TRAP => 1 }[rec.category] || 0
      name = rec.display_name.to_s
      base += 1 if ALLOWLIST.any? { |n| name.start_with?(n) }

      text = "#{rec.note} #{rec.timing}".downcase
      up   = [ UP_KEYWORDS.count { |k| text.include?(k) }, 2 ].min
      down = [ DOWN_KEYWORDS.count { |k| text.include?(k) }, 2 ].min

      base + up - down
    end

    def bucket(score)
      return :high if score >= 3
      return :medium if score >= 1

      :low
    end
  end
end
