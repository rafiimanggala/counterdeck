# Stable JSON shape for a single printing (variant) in the public API.
class PrintingSerializer
  def initialize(printing)
    @p = printing
  end

  def as_json(*)
    {
      set_name: @p.set_name,
      set_code: @p.set_code,
      rarity: @p.set_rarity,
      rarity_code: @p.set_rarity_code,
      rarity_tier: @p.rarity_tier,
      edition: @p.edition,
      foil: @p.foil,
      promo: @p.promo,
      language: @p.language,
      price: @p.set_price
    }
  end
end
