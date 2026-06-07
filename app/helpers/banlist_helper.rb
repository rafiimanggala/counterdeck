module BanlistHelper
  # MD-Meta-style "allowed copies" disc: a red bar = 0 (Forbidden), an amber "1"
  # = Limited, a yellow "2" = Semi-Limited. Severity reads red -> amber -> yellow
  # and the glyph is the legal copy count, exactly like masterduelmeta.com.
  BAN_DISC = {
    "forbidden" => "#dc2626",     # red-600
    "limited" => "#f59e0b",       # amber-500
    "semi_limited" => "#facc15"   # yellow-400
  }.freeze

  BAN_FULL_LABEL = {
    "forbidden" => "Forbidden (0)",
    "limited" => "Limited (1)",
    "semi_limited" => "Semi-Limited (2)",
    "unlimited" => "Unlimited (3)"
  }.freeze

  BAN_TEXT_COLOR = {
    "forbidden" => "text-rose-300",
    "limited" => "text-amber-300",
    "semi_limited" => "text-yellow-300",
    "unlimited" => "text-slate-400"
  }.freeze

  # Returns the SVG disc for a restricted status, or nil for unlimited.
  def ban_icon(status, size: "1rem")
    s = status.to_s
    disc = BAN_DISC[s]
    return nil unless disc

    inner =
      if s == "forbidden"
        %(<rect x="4" y="14.5" width="24" height="3" rx="1.5" fill="#fff"/>)
      else
        %(<text x="16" y="22.5" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif" font-size="17" font-weight="800" fill="#1c1917">#{s == 'limited' ? '1' : '2'}</text>)
      end

    raw %(<svg viewBox="0 0 32 32" width="#{size}" height="#{size}" role="img" aria-label="#{BAN_FULL_LABEL[s]}" class="inline-block shrink-0 drop-shadow"><circle cx="16" cy="16" r="15" fill="#{disc}" stroke="rgba(0,0,0,.4)" stroke-width="1.5"/>#{inner}</svg>)
  end
end
