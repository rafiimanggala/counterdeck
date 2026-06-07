module MatchupHelper
  # Traffic-light readiness from impact-weighted coverage. Plain words for laypeople:
  # Weak = you barely answer it, Thin = some answers, Ready = solidly covered.
  MATCHUP_STATUS = {
    weak:  { label: "Weak",  dot: "bg-rose-500",    pill: "bg-rose-500/15",    text: "text-rose-300" },
    thin:  { label: "Thin",  dot: "bg-amber-400",   pill: "bg-amber-500/15",   text: "text-amber-300" },
    ready: { label: "Ready", dot: "bg-emerald-400", pill: "bg-emerald-500/15", text: "text-emerald-300" }
  }.freeze

  def matchup_status_key(pct)
    pct >= 60 ? :ready : (pct >= 30 ? :thin : :weak)
  end

  def matchup_status(pct)
    MATCHUP_STATUS.fetch(matchup_status_key(pct))
  end

  def matchup_bar_color(pct)
    matchup_status(pct)[:dot]
  end
end
