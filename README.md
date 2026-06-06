# CounterDeck

A Yu-Gi-Oh! card-data platform and counter cheat-sheet, built with Ruby on Rails 8.

Pick the deck your opponent is playing and get an instant, scannable answer: which
combo pieces to **STOP**, which hand traps to **HOLD**, and which board breakers to
**BREAK** their board with. The slow, document-style matchup write-ups on existing meta
sites turned into a sub-5-second mobile cheat-sheet.

Under the cheat-sheet sits a real card-data engine: ingestion from the YGOPRODeck API,
normalized printings/variants/multi-vendor pricing, a format-aware banlist (including a
**derived Master Duel banlist** the API does not expose), a versioned JSON API, and an
OCR card-scan feature.

## Why this exists

Built as a focused demonstration of the data-platform work that powers trading-card
APIs: ingest messy real-world card data, model one-card-to-many-printings-to-many-prices,
reconcile sources, validate correctness, and serve it through a clean API, with a
consumer-facing counter tool on top. Made by someone who actually plays the game.

## Stack

- Ruby 4.0 / Rails 8.1
- PostgreSQL (Docker)
- Hotwire (Turbo + Stimulus) + Tailwind CSS
- Solid Queue (background ingestion)
- Data source: [YGOPRODeck API v7](https://ygoprodeck.com/api-guide/)

## Data model

| Model | Purpose |
|-------|---------|
| `Card` | Core card record (name, type, stats, archetype, text) |
| `Printing` | One physical printing/variant of a card (set, rarity, price) |
| `Price` | Per-vendor market price (TCGplayer, Cardmarket, eBay, ...) |
| `CardImage` | Self-hosted card art (no hotlinking, per API terms) |
| `BanlistEntry` | Format-aware ban status (tcg / ocg / goat / **md**) |
| `Deck` | A meta/tournament deck a player needs to counter |
| `CounterRecommendation` | A key card / hand trap / board breaker for a deck |

## Local setup

```bash
# Postgres via Docker
docker run -d --name counterdeck-pg \
  -e POSTGRES_USER=counterdeck -e POSTGRES_PASSWORD=counterdeck \
  -e POSTGRES_DB=counterdeck_development -p 5435:5432 postgres:16-alpine

bin/rails db:prepare
bin/rails server
```

## Status

Work in progress. See the commit history for build phases.
