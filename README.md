# CounterDeck

I built this because I kept losing to meta decks I did not know how to answer.

I play a lot of Yu-Gi-Oh, mostly on **Master Duel** (Konami's official digital game). The problem was never my own deck, it was sitting across from some combo deck I had never studied, watching it set up an unbreakable board, and having no idea which of my cards actually mattered. The matchup write-ups on existing meta sites are thorough but slow to read mid-ladder.

So I made myself a cheat-sheet. Pick the deck the opponent is on and get one scannable answer: what to **STOP** (the combo starters worth interrupting), what to **HOLD** (the hand traps that actually do something this matchup), and what to **BREAK** (the board breakers for when they get to set up first). It is mobile-first and meant to be read in a few seconds, with a format toggle so the legality reflects the format I am actually queueing in.

Then, because the card data turned out to be a fun data-engineering problem in its own right, I kept going: a real ingestion pipeline, multi-source reconciliation, variant normalization, and a versioned JSON API. That half is below the fold here, because the cheat-sheet is the point. This is a personal Rails side-project, not a product.

## What it does

- **Counter cheat-sheet (the reason it exists).** Per-deck interruption points (STOP), hand traps (HOLD), and board breakers (BREAK), plus the deck's key cards, a going-first-vs-second note, and a plain-language beginner explanation. Mobile-first, with a Master-Duel-vs-TCG format toggle that re-checks card legality against the right banlist.
- **Build-your-own-deck matchups.** Enter the deck you actually play, then run it head to head against a meta deck to see the reverse: which of *your* cards line up as the counters.
- **OCR card scanner.** Snap a photo of a physical card, Tesseract reads the title band, `pg_trgm` fuzzy-matches it to the catalog, and you see what it counters. It declines low-confidence reads instead of guessing.

## Under the hood: the data engine

The cheat-sheet sits on a real card-data layer. The source feed (the free YGOPRODeck API) is generous: it exposes printings, set rarities, and multi-vendor prices, so the engine also models the physical side of the game properly, not just the digital game I play. I used that as an excuse to push the data engineering further.

### The flagship problem: the Master Duel banlist does not exist in the API

This is the part I am proudest of. YGOPRODeck only exposes three banlists: `ban_tcg`, `ban_ocg`, and `ban_goat`. Master Duel runs its own separate Forbidden & Limited list, and it is **not in the API at all**. A naive Master-Duel-first app would just borrow the TCG list and ship silently-wrong Forbidden/Limited tags, which for a counter tool is worse than useless.

CounterDeck instead **derives and reconciles** the Master Duel list from a second source (a curated snapshot in `db/seeds/md_banlist.json`, rebuilt from the masterduelmeta.com Forbidden & Limited data), imports it as `BanlistEntry` rows with `format: "md"`, and then reconciles it against the TCG status to surface every **divergence**. The textbook example: `Maxx "C"` is Forbidden in the TCG but Limited in Master Duel. That divergence is computed, stored, and shown in the admin data-quality view rather than swept under the rug. Every card response carries all three formats side by side:

```json
{ "name": "Maxx \"C\"", "banlist": { "tcg": "forbidden", "ocg": "unlimited", "md": "limited" } }
```

### Variant modelling (the physical side, done properly)

YGOPRODeck gives free-text rarity strings ("Quarter Century Secret Rare", "Starlight Rare", and so on) that are inconsistent across sets and languages. `Printing.classify` is the single place that maps that mess onto a stable, queryable variant shape: a normalized `rarity_tier`, plus a derived `edition`, `foil`, and `promo`. Each printing also carries a stored `language`. So one card fans out into many printings you can actually filter and reason about. Exposed at:

```
GET /api/v1/cards/:id/printings?foil=true&rarity_tier=secret&edition=1st&language=en&promo=true
```

### Multi-source reconciliation with stored provenance

`DataReconciler` merges card data from multiple sources by priority: for every reconciled field, the highest-priority source with a non-nil value wins. The interesting bit is what happens on disagreement. Conflicts are never silently dropped: both the **provenance** (which source won each field) and the **conflicts** (where sources disagreed, with all candidate values) are written to the card's JSONB `metadata`, so they stay queryable afterward. Re-running with the same sources is idempotent. You can read the full audit trail per card:

```
GET /api/v1/cards/:id/audit
```

returns `sources`, `provenance`, `conflicts`, a computed `banlist_divergence` (tcg vs md), and a `price_outlier` flag (when the vendor-price spread looks suspicious, max more than 3x the min).

## Stack

- Ruby 4.0.2, Rails 8.1
- PostgreSQL with `pg_trgm` (run via Docker locally)
- Hotwire (Turbo + Stimulus) and Tailwind CSS for the cheat-sheet UI
- Tesseract (OCR) and libvips (image crop/resize) for the scanner
- Data source: [YGOPRODeck API v7](https://ygoprodeck.com/api-guide/)

## Data model

| Model | Purpose |
|-------|---------|
| `Card` | Core card record (name, type, stats, archetype, text). Carries a JSONB `metadata` sidecar for reconciliation provenance and conflicts. |
| `Printing` | One printing/variant of a card (set, rarity, derived `rarity_tier` / `edition` / `foil` / `promo`, plus `language` and price). |
| `Price` | Per-vendor market price (Cardmarket, TCGplayer, eBay, Amazon, CoolStuffInc), unique per source. |
| `CardImage` | Self-hosted card art (no hotlinking, per the API terms). |
| `BanlistEntry` | Format-aware ban status: `tcg`, `ocg`, `goat`, and the derived **`md`** (Master Duel). |
| `Deck` | A meta deck a player needs to counter (tier, formats, status, confidence). |
| `CounterRecommendation` | One key card / hand trap / board breaker for a deck, autolinked to the catalog. Can name multiple cards (e.g. "Effect Veiler / Infinite Impermanence") so each gets its art. |

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
bin/rails cards:ingest_meta        # cards, printings (variants), prices, banlists from YGOPRODeck
bin/rails cards:import_md_banlist   # derive the Master Duel banlist + report divergences
bin/rails db:seed                   # load the meta-deck counter sheets

# 4. Run
bin/dev   # or: bin/rails server
```

The OCR scanner also needs `tesseract` and `vips` (`brew install tesseract vips`).

To re-derive variant fields on printings that predate the variant model, there is `bin/rails printings:backfill_variants`.

## API

A versioned JSON API sits alongside the Hotwire UI, with pagination, filtering, ETags (`stale?`), an in-process rate limit (100 req/min), and an OpenAPI spec at `public/api/openapi.yaml`.

```bash
# Cards: search, archetype filter, banlist filter
curl "localhost:3000/api/v1/cards?q=Maxx&banlist_format=md&banlist_status=limited"

# One card (detailed): text, image, printings, prices, data_quality
curl "localhost:3000/api/v1/cards/12345"

# Variant drill-down
curl "localhost:3000/api/v1/cards/12345/printings?foil=true&rarity_tier=secret"

# Reconciliation audit trail
curl "localhost:3000/api/v1/cards/12345/audit"

# Decks + full counter sheet
curl "localhost:3000/api/v1/decks/branded"
```

Card IDs accept either the internal id or the YGOPRODeck `ygo_id`.

## Deploy

The live instance runs on **DigitalOcean App Platform** (`.do/app.yaml`), containerized via the `Dockerfile`, backed by a free external **Neon** Postgres supplied through the `DATABASE_URL` secret. Live URL: [counterdeck-gxnky.ondigitalocean.app](https://counterdeck-gxnky.ondigitalocean.app).

The app spec runs Puma directly (`./bin/rails server`) so it binds DigitalOcean's `$PORT` (8080), with a `/up` health check. The image entrypoint runs `db:prepare` on boot (schema load plus `pg_trgm`), which is a safe no-op once Neon is migrated. Card data is loaded once from a shell:

```bash
bin/rails cards:ingest_meta        # cards, printings, prices, banlists (YGOPRODeck)
bin/rails cards:import_md_banlist   # derive + reconcile the Master Duel banlist
bin/rails db:seed                   # (re)link the counter sheets to the catalog
```

It is tuned to fit a 1GB instance: single-process Puma, `MALLOC_ARENA_MAX=2`, jemalloc, in-process jobs (`:async`) and cache (`:memory_store`), so there is no Redis or worker process to run. Because it is plain Docker plus an external Postgres, it is portable: the repo also ships a `render.yaml` Blueprint as an alternate target, but DigitalOcean is the one that is live.

## Tests

```bash
bin/rails test
```

86 tests, all green. They cover model validations, banlist normalization, variant classification, ingestion idempotency and dedup, the Master Duel banlist reconciliation, the multi-source `DataReconciler` (priority, provenance, conflicts), and the JSON API contract.

## Data challenges (and how I solved them)

- **The Master Duel banlist is not in the API.** YGOPRODeck exposes `ban_tcg` / `ban_ocg` / `ban_goat` only. Rather than ship a silently-wrong list, CounterDeck maintains the MD list from a second source and reconciles it against the TCG status, surfacing every divergence (Maxx "C" being the headline case) in the admin data-quality view.
- **Messy rarity strings.** Set rarities are free text and inconsistent across sets. `Printing.classify` normalizes them into a stable `rarity_tier` plus `foil` / `promo` / `edition`, so variants are queryable instead of being a string blob.
- **Sources that disagree.** Real catalogs blend feeds that conflict. `DataReconciler` resolves by priority but stores the provenance and the conflict in JSONB, so the divergence is auditable instead of hidden.
- **No image hotlinking.** YGOPRODeck blacklists hotlinkers, so images are downloaded and self-hosted under `public/card_images/` (git-ignored).
- **Alt-art and reprint dedup.** A card has many printings across sets and rarities; ingestion dedups on `(card, set_code, set_rarity, edition)` and keeps per-vendor prices unique per source, so re-syncing never duplicates rows.
- **OCR on busy card art.** Full-card OCR is noisy, so the scanner crops and upscales the top name band, OCRs it as a single line, and fuzzy-matches with a `pg_trgm` threshold that declines low-confidence reads instead of asserting a wrong card.

## Notes

Counter data is AI-drafted and human-reviewed (marked `draft` until I verify it in the admin), and the curated meta reads are dated so the data is honest about how current it is. Not affiliated with Konami. Card data courtesy of YGOPRODeck.