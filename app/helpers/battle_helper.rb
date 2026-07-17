module BattleHelper
  # Readiness ring geometry for the VS gauge. An SVG circle of radius RING_R;
  # the progress arc length is weighted_coverage_pct of the circumference,
  # clamped to >= 3% so even 0% readiness shows a visible sliver (mirrors the
  # [pct, 3].max idiom the coverage bar already uses).
  RING_R = 54

  def readiness_ring(pct)
    shown = [ [ pct.to_i, 0 ].max, 100 ].min
    circ = 2 * Math::PI * RING_R
    dash = circ * [ shown, 3 ].max / 100.0
    { circumference: circ.round(2), dash: dash.round(2), gap: (circ - dash).round(2) }
  end

  # SVG stroke color class for the ring, matched to the traffic-light status.
  # Literal class strings so Tailwind's JS/erb scan includes them in the build.
  def readiness_stroke(pct)
    case matchup_status_key(pct)
    when :ready then "stroke-emerald-400"
    when :thin  then "stroke-amber-400"
    else             "stroke-rose-500"
    end
  end

  # Tier strip color for the coverage meter cells (matches impact_chip strips).
  def tier_cell_color(tier)
    { high: "bg-rose-500", medium: "bg-amber-400", low: "bg-sky-400" }[tier.to_sym] || "bg-slate-600"
  end

  # A match is dropped when the very next words negate it ("Ash Blossom does not
  # work here"), so the UI never illustrates a card the line tells you to avoid.
  NEGATION_AFTER = /\A[\s,]*(?:does\s*n[o']?t|do\s+not|don[o']?t|cannot|can[o']?t|will\s+not|won[o']?t|never|whiff)/i

  # Find the catalog cards a free-text play/interruption line actually names, so
  # the prose can be illustrated with real card art. The plays/interruptions
  # data carries no card link, so we match by name against a given pool of
  # CounterRecommendations (e.g. the enemy's key cards for a THEY line, the
  # recommended outs for a YOU line) and keep only those with downloadable art.
  #
  # Defences against wrong art (all reproduced against the live data):
  # - word-boundary lookarounds so "Despia" never fires inside "Despian";
  # - ambiguous shared aliases (a bare "Sky Striker Ace" / "Elfnotes" carried by
  #   more than one card) are suppressed, so only a unique full name can match;
  # - longest-needle-first with span claiming so the most specific name wins;
  # - a negation guard (see NEGATION_AFTER).
  # Returns Cards ordered by first appearance, deduped, capped at `limit`.
  def cards_in_text(text, recs, limit: 4)
    return [] if text.blank?

    low = text.downcase
    raw = []
    Array(recs).each do |rec|
      cards = rec.display_cards
      next if cards.empty?

      # 1) the catalog (canonical) name of every card the rec names.
      cards.each do |card|
        card_name_aliases(card.name).each { |a| raw << [ card, a.downcase ] if a.length >= 4 }
      end
      # 2) the prose/draft spellings from the rec's own typed name ("Crosia" for
      # the card catalogued as "Radiant Typhoon Krosea"), mapped to the card it
      # describes, so the spine illustrates the words the write-up actually uses.
      prose_fragments(rec.card_name).each do |frag|
        target = nearest_card(frag, cards)
        next unless target

        card_name_aliases(frag).each { |a| raw << [ target, a.downcase ] if a.length >= 4 }
      end
    end
    raw.uniq!

    # An alias shared by more than one distinct card is too generic to identify
    # one card on its own; drop it (the cards keep their unique full names).
    shared = raw.group_by { |_card, needle| needle }
                .select { |_needle, list| list.map { |c, _| c.id }.uniq.size > 1 }
                .keys
    candidates = raw.reject { |_card, needle| shared.include?(needle) }.uniq
    candidates.sort_by! { |_card, needle| -needle.length }

    claimed = []
    picks = []
    candidates.each do |card, needle|
      pos = low =~ /(?<!\w)#{Regexp.escape(needle)}(?!\w)/
      next unless pos

      finish_at = pos + needle.length
      next if claimed.any? { |range| range.cover?(pos) || (pos...finish_at).cover?(range.first) }
      next if picks.any? { |picked, _| picked.id == card.id }
      next if low[finish_at, 26].to_s.match?(NEGATION_AFTER)

      claimed << (pos...finish_at)
      picks << [ card, pos ]
    end

    picks.sort_by(&:last).map(&:first).first(limit)
  end

  # A card's full name plus the aliases prose tends to use for it:
  # - a quote-stripped form, so 'Maxx "C"' matches plain "Maxx C";
  # - its leading significant segment ("Ash Blossom" from "Ash Blossom & Joyous
  #   Spring", "Zalen" from "Zalen the Shackled Dragon");
  # - its trailing distinctive segment ("Shizuku" from "Sky Striker Ace -
  #   Shizuku", "Multirole" from "... - Multirole").
  # Segments under 5 chars are dropped to avoid spurious hits.
  def card_name_aliases(name)
    return [] if name.blank?

    full = name.strip
    list = [ full ]

    stripped = full.gsub(/["']/, "").squeeze(" ").strip
    list << stripped if stripped.present? && stripped != full

    lead = full.split(%r{\s+(?:the|of|&|-|/|=)\s+|[,:("]}i).first&.strip
    list << lead if lead.present? && lead.length >= 5

    tail = full.split(%r{\s+-\s+|[:/]}).last&.strip
    list << tail if tail.present? && tail.length >= 5 && tail != full

    # last word of an archetype-style name ("Swen" from "Radiant Typhoon Swen"),
    # which is how prose usually refers to such cards.
    words = full.split(/\s+/)
    if words.size >= 3 && (lw = words.last.gsub(/[^A-Za-z0-9]/, "")).length >= 4
      list << lw
    end

    list.uniq
  end

  private

  # The individual card-name fragments a rec's typed name lists, before catalog
  # normalisation (parentheticals dropped): "A / B (note)" -> ["A", "B"].
  def prose_fragments(card_name)
    return [] if card_name.blank?

    card_name.to_s.gsub(/\([^)]*\)/, " ").split(%r{\s+/\s+|;}).map(&:strip).reject(&:blank?)
  end

  # Which of a rec's display cards a prose fragment refers to: the one sharing the
  # most words (so "Mandate" maps to "Radiant Typhoon Mandate", not its sibling).
  # A single-card rec always maps to that card; no shared word -> no mapping.
  def nearest_card(fragment, cards)
    return cards.first if cards.size == 1

    fwords = fragment.downcase.scan(/[a-z0-9]+/)
    best = cards.max_by { |c| (c.name.downcase.scan(/[a-z0-9]+/) & fwords).size }
    shared = (best.name.downcase.scan(/[a-z0-9]+/) & fwords).size
    shared.positive? ? best : nil
  end
end
