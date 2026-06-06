# Bridges the local catalog (408 meta cards) and the full YGOPRODeck database
# (~13k cards) so the deck builder can search and add ANY card on demand.
#
#   search(q)        -> merged local + remote name matches (no ingest yet, cheap)
#   ensure(ygo_id)   -> guarantees the card exists locally (fetch + ingest + art)
#
# Remote calls are best-effort: if YGOPRODeck is unreachable we degrade to the
# local catalog rather than failing the request.
class CardProvisioner
  Suggestion = Struct.new(:ygo_id, :name, :card_kind, :frame_type, :archetype, :card, keyword_init: true) do
    def in_catalog? = card.present?
  end

  def initialize(client: YgoprodeckClient.new, logger: Rails.logger)
    @client = client
    @logger = logger
  end

  # Up to `limit` name matches, local catalog first, then remote-only cards.
  def search(query, limit: 20)
    q = query.to_s.strip
    return [] if q.length < 2

    local = Card.search_name(q).order(:name).limit(limit).to_a
    suggestions = local.map { |c| suggestion_from_card(c) }
    seen = local.map(&:ygo_id).to_set

    if suggestions.size < limit
      remote_cards(q).each do |data|
        next if seen.include?(data["id"])

        seen << data["id"]
        suggestions << suggestion_from_api(data)
        break if suggestions.size >= limit
      end
    end

    suggestions
  end

  # Returns a persisted Card for ygo_id, ingesting it from YGOPRODeck if absent.
  def ensure(ygo_id)
    id = ygo_id.to_i
    return nil if id.zero?

    existing = Card.find_by(ygo_id: id)
    return existing if existing

    api = @client.cards(id: id)
    return nil if api.empty?

    # No downloader here: art is fetched lazily (and as a small thumbnail) by
    # CardImagesController the first time the card's image is actually rendered.
    CardIngestor.new.call(api)
    Card.find_by(ygo_id: id)
  rescue YgoprodeckClient::Error => e
    @logger.warn("[CardProvisioner] ensure(#{ygo_id}) failed: #{e.class} #{e.message}")
    nil
  end

  private

  def remote_cards(query)
    @client.cards(fname: query)
  rescue YgoprodeckClient::Error => e
    @logger.warn("[CardProvisioner] remote search '#{query}' failed: #{e.message}")
    []
  end

  def suggestion_from_card(card)
    Suggestion.new(
      ygo_id: card.ygo_id, name: card.name, card_kind: card.card_kind,
      frame_type: card.frame_type, archetype: card.archetype, card: card
    )
  end

  def suggestion_from_api(data)
    Suggestion.new(
      ygo_id: data["id"], name: data["name"], card_kind: data["type"],
      frame_type: data["frameType"], archetype: data["archetype"], card: nil
    )
  end
end
