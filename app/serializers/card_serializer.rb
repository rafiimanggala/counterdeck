# Plain-Ruby serializer (no gem) -> stable JSON shape for the public API.
class CardSerializer
  def initialize(card, detailed: false)
    @card = card
    @detailed = detailed
  end

  def as_json(*)
    base = {
      id: @card.id,
      ygo_id: @card.ygo_id,
      name: @card.name,
      type: @card.card_kind,
      frame_type: @card.frame_type,
      attribute: @card.ygo_attribute,
      race: @card.race,
      atk: @card.atk,
      def: @card.defense,
      level: @card.level,
      archetype: @card.archetype,
      banlist: {
        tcg: @card.banlist_status("tcg"),
        ocg: @card.banlist_status("ocg"),
        md: @card.banlist_status("md")
      }
    }
    return base unless @detailed

    base.merge(
      text: @card.card_text,
      image: @card.primary_image&.local_path,
      printings: @card.printings.map { |p| printing(p) },
      prices: @card.prices.map { |pr| price(pr) }
    )
  end

  private

  def printing(p)
    { set_name: p.set_name, set_code: p.set_code, rarity: p.set_rarity, price: p.set_price }
  end

  def price(pr)
    { source: pr.source, amount: pr.amount, currency: pr.currency }
  end
end
