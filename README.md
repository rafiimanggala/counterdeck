# CounterDeck

A Yu-Gi-Oh! card-data platform and counter cheat-sheet, built with Ruby on Rails 8.

Pick the deck your opponent is playing and get an instant, scannable answer: which
combo pieces to **STOP**, which hand traps to **HOLD**, and which board breakers to
**BREAK** their board with. The slow, document-style matchup write-ups on existing
meta sites, turned into a sub-5-second, mobile-first cheat-sheet.

Under the cheat-sheet sits a real card-data engine: ingestion from the YGOPRODeck
API, normalized printings / variants / multi-vendor pricing, a **format-aware banlist
that derives the Master Duel list the API does not expose**, a versioned JSON API,
and an OCR card scanner. Built by someone who actually plays the game.

## Features

- **Counter cheat-sheet** — per meta deck: interruption points (STOP), hand traps
  (HOLD), board breakers (BREAK), key cards, going-first-vs-second, beginner notes.
  Mobile-first, format toggle (Master Duel vs TCG) that re-checks legality live.
- **Ingestion pipeline** — pulls cards from YGOPRODeck, normalizes one-card →
  many-printings → many-vendor-prices, dedups alt-arts, self-hosts images. Idempotent.
- **Derived Master Duel banlist** — reconciled against the TCG list to surface
  divergences (e.g. Maxx "C": Forbidden in TCG, Limited in Master Duel).
- **Versioned JSON API** — `/api/v1/cards` and `/api/v1/decks` with pagination,
  filtering, ETags, rate limiting, and an OpenAPI spec.
- **OCR card scanner** — snap a physical card → Tesseract OCR (name-band crop) →
  `pg_trgm` fuzzy match → see what it counters. 12/12 on staples, zero false positives.
- **Admin tooling** — fast counter input (nested form with card autolink) and a
  data-quality dashboard (banlist divergences, unlinked counters, drafts).

## Stack

- Ruby 4.0 / Rails 8.1
- PostgreSQL (+ `pg_trgm`), via Docker
- Hotwire (Turbo + Stimulus) + Tailwind CSS
- Tesseract (OCR) + libvips (image crop) for the scanner
- Data source: [YGOPRODeck API v7](https://ygoprodeck.com/api-guide/)

## Data model

| Model | Purpose |
|-------|---------|
| `Card` | Core card record (name, type, stats, archetype, text) |
| `Printing` | One physical printing/variant (set, rarity, price) |
| `Price` | Per-vendor market price (TCGplayer, Cardmarket, eBay, ...) |
| `CardImage` | Self-hosted card art (no hotlinking, per API terms) |
| `BanlistEntry` | Format-aware ban status (`tcg` / `ocg` / `goat` / **`md`**) |
| `Deck` | A meta/tournament deck a player needs to counter |
| `CounterRecommendation` | A key card / hand trap / board breaker for a deck |

## Local setup

```bash
# 1. Postgres via Docker (port 5435)
docker run -d --name counterdeck-pg \
  -e POSTGRES_USER=counterdeck -e POSTGRES_PASSWORD=counterdeck \
  -e POSTGRES_DB=counterdeck_development -p 5435:5432 postgres:16-alpine

# 2. Dependencies, DB, schema
bundle install
bin/rails db:prepare

# 3. Populate the catalog + banlists + counter sheets
bin/rails cards:ingest_meta        # cards, printings, prices, banlists from YGOPRODeck
bin/rails cards:import_md_banlist   # derive Master Duel banlist + report divergences
bin/rails db:seed                   # load the meta-deck counter sheets

# 4. Run
bin/dev   # or: bin/rails server
```

OCR scanner also needs `tesseract` and `vips` (`brew install tesseract vips`).

## API

```bash
curl "localhost:3000/api/v1/cards?q=Maxx&banlist_format=md"
curl "localhost:3000/api/v1/decks/kewl-tune"
```

Spec: `public/api/openapi.yaml`. Card responses include the format-aware banlist:

```json
{ "name": "Maxx \"C\"", "banlist": { "tcg": "forbidden", "ocg": "unlimited", "md": "limited" } }
```

## Tests

```bash
bin/rails test
```

Covers model validations, banlist normalization, ingestion idempotency/dedup, the
Master Duel banlist reconciliation, and the JSON API contract.

## Data challenges (and how they were solved)

- **The Master Duel banlist does not exist in the API.** YGOPRODeck exposes
  `ban_tcg` / `ban_ocg` / `ban_goat` only. A naive Master-Duel build would ship
  silently-wrong Forbidden/Limited tags. CounterDeck maintains the MD list from a
  second source (`db/seeds/md_banlist.json`) and reconciles it against the TCG
  status, surfacing every divergence in the admin data-quality view.
- **No image hotlinking.** YGOPRODeck IP-blacklists hotlinkers, so images are
  downloaded and self-hosted under `public/card_images/` (git-ignored).
- **Alt-art / reprint dedup.** A card has many printings across sets and rarities;
  ingestion dedups on `(card, set_code, set_rarity)` and keeps per-vendor prices
  unique per source, so re-syncing never duplicates rows.
- **OCR on busy card art.** Full-card OCR is noisy, so the scanner crops and upscales
  the top "name band", OCRs it as a single line, and fuzzy-matches with a `pg_trgm`
  similarity threshold that declines low-confidence reads instead of guessing wrong.

## Notes

Counter data is AI-drafted and human-reviewed (marked `draft` until verified in the
admin). Not affiliated with Konami. Card data courtesy of YGOPRODeck.
