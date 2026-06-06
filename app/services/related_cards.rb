# Suggests cards to add next: archetype-mates of what is already in the deck,
# topped up with format-defining staples. Pulled from the local catalog so the
# panel renders instantly (the user can still search the full DB to add anything).
class RelatedCards
  STAPLE_NAMES = [
    'Maxx "C"', "Ash Blossom & Joyous Spring", "Effect Veiler",
    "Infinite Impermanence", "Nibiru, the Primal Being", "Called by the Grave",
    "Triple Tactics Talent", "Forbidden Droplet", "Harpie's Feather Duster"
  ].freeze

  def initialize(user_deck, limit: 12)
    @deck = user_deck
    @limit = limit
  end

  def suggestions
    owned = @deck.card_id_set
    out = []

    top_archetypes.each do |arch|
      break if out.size >= @limit

      Card.where(archetype: arch)
          .where.not(id: (owned.to_a + out.map(&:id)))
          .order(:name)
          .limit(@limit - out.size)
          .each { |c| out << c }
    end

    if out.size < @limit
      Card.where(name: STAPLE_NAMES)
          .where.not(id: (owned.to_a + out.map(&:id)))
          .each { |c| out << c }
    end

    out.uniq.first(@limit)
  end

  private

  # Archetypes present in the deck, most-used first.
  def top_archetypes
    @deck.deck_entries
         .filter_map { |e| e.card&.archetype.presence }
         .tally
         .sort_by { |_arch, count| -count }
         .map(&:first)
  end
end
