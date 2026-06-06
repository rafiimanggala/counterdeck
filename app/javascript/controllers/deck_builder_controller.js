import { Controller } from "@hotwired/stimulus"

// Master-Duel-style instant deck builder. The whole local catalog is loaded once
// into memory, so search/filter is instant and client-side. Adding/adjusting
// cards is optimistic (DOM updates immediately, the server persists in the
// background) and the expensive matchups frame is refreshed only after edits
// settle - never on the click itself.
export default class extends Controller {
  static targets = ["pool", "search", "main", "extra", "side", "count", "empty", "remoteToggle", "flash"]
  static values = {
    indexUrl: String,
    persistUrl: String,
    searchUrl: String,
    matchupsUrl: String,
    deck: Array,
  }

  EXTRA_FRAMES = ["fusion", "synchro", "xyz", "link"]

  connect() {
    this.index = []
    this.remote = []
    this.searchAll = false
    this.q = ""
    this.typeFilter = ""
    this.attrFilter = ""
    this.searchTimer = null
    this.matchupTimer = null
    this.pendingPersist = new Map()

    // deck: Map "zone:ygo" -> {ygo, cardId, name, kind, img, zone, qty}
    this.deck = new Map()
    for (const e of this.deckValue) {
      this.deck.set(`${e.zone}:${e.ygo}`, { ...e })
    }
    this.renderDeck()
    this.loadIndex()
  }

  async loadIndex() {
    try {
      const res = await fetch(this.indexUrlValue, { headers: { Accept: "application/json" } })
      if (res.ok) this.index = await res.json()
    } catch { /* search still works once index loads; ignore */ }
  }

  // ---- search / filter -------------------------------------------------

  onInput() {
    this.q = this.searchTarget.value.trim().toLowerCase()
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => this.runSearch(), 140)
  }

  setType(event) {
    const v = event.currentTarget.dataset.value
    this.typeFilter = this.typeFilter === v ? "" : v
    this.markActive("type", this.typeFilter)
    this.runSearch()
  }

  setAttr(event) {
    const v = event.currentTarget.dataset.value
    this.attrFilter = this.attrFilter === v ? "" : v
    this.markActive("attr", this.attrFilter)
    this.runSearch()
  }

  markActive(group, value) {
    this.element.querySelectorAll(`[data-filter="${group}"]`).forEach((el) => {
      const on = el.dataset.value === value
      el.classList.toggle("border-violet-500", on)
      el.classList.toggle("text-violet-300", on)
      el.classList.toggle("border-slate-800", !on)
      el.classList.toggle("text-slate-400", !on)
    })
  }

  async toggleRemote(event) {
    this.searchAll = event.currentTarget.checked
    await this.runSearch()
  }

  matchesFilters(c) {
    if (this.typeFilter) {
      const kind = (c.kind || "").toLowerCase()
      if (this.typeFilter === "monster" && !kind.includes("monster")) return false
      if (this.typeFilter === "spell" && !kind.includes("spell")) return false
      if (this.typeFilter === "trap" && !kind.includes("trap")) return false
    }
    if (this.attrFilter && (c.attr || "") !== this.attrFilter) return false
    return true
  }

  STAPLES = ['Maxx "C"', "Ash Blossom & Joyous Spring", "Effect Veiler", "Infinite Impermanence", "Nibiru, the Primal Being", "Called by the Grave", "Triple Tactics Talent", "Forbidden Droplet"]

  // When the search box is empty, show useful suggestions instead of nothing:
  // archetype-mates of what's already in the deck, then staples.
  suggestions() {
    const owned = new Set([...this.deck.values()].map((e) => e.ygo))
    const archCount = {}
    for (const e of this.deck.values()) {
      const a = this.lookup(e.ygo)?.archetype
      if (a) archCount[a] = (archCount[a] || 0) + 1
    }
    const archs = Object.keys(archCount).sort((a, b) => archCount[b] - archCount[a])
    const out = []
    const seen = new Set()
    for (const a of archs) {
      for (const c of this.index) {
        if (c.archetype === a && !owned.has(c.ygo_id) && !seen.has(c.ygo_id)) { out.push(c); seen.add(c.ygo_id) }
      }
      if (out.length >= 18) break
    }
    if (out.length < 18) {
      const names = new Set(this.STAPLES)
      for (const c of this.index) {
        if (names.has(c.name) && !owned.has(c.ygo_id) && !seen.has(c.ygo_id)) { out.push(c); seen.add(c.ygo_id) }
      }
    }
    return out.slice(0, 18)
  }

  async runSearch() {
    let results = []
    if (this.q.length >= 1 || this.typeFilter || this.attrFilter) {
      results = this.index.filter((c) => {
        if (this.q && !(c.name || "").toLowerCase().includes(this.q)) return false
        return this.matchesFilters(c)
      })
    } else {
      results = this.suggestions()
    }

    // Optionally augment with the full YGOPRODeck DB (server, cached) for names
    // the local catalog doesn't have.
    if (this.searchAll && this.q.length >= 2) {
      try {
        const res = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(this.q)}`, { headers: { Accept: "application/json" } })
        if (res.ok) {
          const have = new Set(results.map((r) => r.ygo_id ?? r.ygo))
          for (const r of await res.json()) {
            const ygo = r.ygo_id
            if (!have.has(ygo)) results.push({ ygo_id: ygo, name: r.name, kind: r.kind, attr: null, img: r.image, remote: !r.in_catalog })
          }
        }
      } catch { /* keep local results */ }
    }

    this.renderPool(results.slice(0, 60))
  }

  renderPool(cards) {
    if (!cards.length) {
      this.poolTarget.innerHTML = `<p class="col-span-full py-8 text-center text-sm text-slate-600">${this.q || this.typeFilter || this.attrFilter ? "No cards match." : "Search or filter to find cards."}</p>`
      return
    }
    this.poolTarget.innerHTML = cards.map((c) => this.poolTile(c)).join("")
  }

  poolTile(c) {
    const ygo = c.ygo_id ?? c.ygo
    const remote = c.remote ? `<span class="absolute right-1 top-1 rounded bg-slate-950/80 px-1 text-[9px] text-slate-300">fetch</span>` : ""
    return `<div class="group relative">
      <button type="button" data-action="deck-builder#add" data-ygo="${ygo}" data-kind="${this.attr(c.kind)}"
        class="block w-full overflow-hidden rounded-lg border border-slate-800 bg-slate-900 transition hover:border-violet-500" title="Add ${this.attr(c.name)}">
        ${this.art(c.img, c.name, "aspect-[59/86] w-full")}
        ${remote}
      </button>
      <button type="button" data-action="card-modal#open" data-url="/cards/${ygo}" aria-label="Details"
        class="absolute bottom-1 right-1 grid h-6 w-6 place-items-center rounded-full bg-slate-950/80 text-xs text-slate-300 opacity-0 transition group-hover:opacity-100 hover:text-violet-300">i</button>
      <div class="mt-1 truncate text-[11px] leading-tight text-slate-400">${this.attr(c.name)}</div>
    </div>`
  }

  // ---- add / adjust / remove (optimistic) ------------------------------

  add(event) {
    const ygo = Number(event.currentTarget.dataset.ygo)
    const kind = event.currentTarget.dataset.kind || ""
    const card = this.lookup(ygo) || { ygo, name: this.attr(event.currentTarget.title.replace(/^Add /, "")), kind, img: null }
    const zone = this.zoneFor(card.kind || kind)
    const key = `${zone}:${ygo}`
    const existing = this.deck.get(key)
    const qty = Math.min((existing?.qty || 0) + 1, 3)
    this.deck.set(key, { ygo, cardId: existing?.cardId, name: card.name, kind: card.kind, img: card.img ?? existing?.img, zone, qty })
    this.renderDeck()
    this.persist(ygo, zone, qty)
  }

  step(event) {
    const { ygo, zone, delta } = event.currentTarget.dataset
    const key = `${zone}:${Number(ygo)}`
    const entry = this.deck.get(key)
    if (!entry) return
    const qty = Math.min(Math.max(entry.qty + Number(delta), 0), 3)
    if (qty === 0) {
      this.deck.delete(key)
    } else {
      entry.qty = qty
    }
    this.renderDeck()
    this.persist(Number(ygo), zone, qty)
  }

  removeCard(event) {
    const { ygo, zone } = event.currentTarget.dataset
    this.deck.delete(`${zone}:${Number(ygo)}`)
    this.renderDeck()
    this.persist(Number(ygo), zone, 0)
  }

  zoneFor(kind) {
    const k = (kind || "").toLowerCase()
    return this.EXTRA_FRAMES.some((f) => k.includes(f)) ? "extra" : "main"
  }

  lookup(ygo) {
    return this.index.find((c) => (c.ygo_id ?? c.ygo) === ygo) ||
           this.remote.find((c) => c.ygo_id === ygo)
  }

  // ---- persistence (debounced per card, last-write-wins) ---------------

  persist(ygo, zone, qty) {
    const key = `${zone}:${ygo}`
    clearTimeout(this.pendingPersist.get(key))
    this.pendingPersist.set(key, setTimeout(async () => {
      const body = new FormData()
      body.append("ygo_id", ygo)
      body.append("zone", zone)
      body.append("quantity", qty)
      try {
        const res = await fetch(this.persistUrlValue, {
          method: "POST",
          headers: { Accept: "application/json", "X-CSRF-Token": this.csrf() },
          body,
        })
        if (res.ok) {
          const data = await res.json()
          // Backfill the catalog id / freshly-ingested art onto the live tile.
          const entry = this.deck.get(key)
          if (entry && data.ok && qty > 0) {
            if (data.img && !entry.img) { entry.img = data.img; this.renderDeck() }
            if (data.card_id) entry.cardId = data.card_id
          }
        } else {
          this.flashError("Couldn't save that change.")
        }
      } catch {
        this.flashError("Network error saving deck.")
      }
      this.scheduleMatchups()
    }, 350))
  }

  scheduleMatchups() {
    clearTimeout(this.matchupTimer)
    this.matchupTimer = setTimeout(() => {
      const frame = document.getElementById("matchups")
      if (frame) frame.src = this.matchupsUrlValue + `?t=${this.deck.size}`
    }, 600)
  }

  // ---- deck rendering --------------------------------------------------

  renderDeck() {
    const zones = { main: [], extra: [], side: [] }
    for (const e of this.deck.values()) zones[e.zone]?.push(e)
    for (const z of ["main", "extra", "side"]) {
      const target = this[`${z}Target`]
      const list = zones[z].sort((a, b) => (a.name || "").localeCompare(b.name || ""))
      if (!this.hasMainTarget) continue
      if (target) target.innerHTML = list.length ? list.map((e) => this.deckTile(e)).join("") : this.zoneEmpty(z)
    }
    if (this.hasCountTarget) {
      const c = (z) => [...this.deck.values()].filter((e) => e.zone === z).reduce((n, e) => n + e.qty, 0)
      this.countTarget.textContent = `${c("main")} main · ${c("extra")} extra · ${c("side")} side`
    }
  }

  deckTile(e) {
    return `<div class="flex gap-2 rounded-lg border border-slate-800 bg-slate-950 p-2">
      <button type="button" data-action="card-modal#open" data-url="/cards/${e.ygo}" class="shrink-0" aria-label="Details for ${this.attr(e.name)}">
        ${this.art(e.img, e.name, "h-16 w-11")}
      </button>
      <div class="flex min-w-0 flex-1 flex-col justify-between">
        <div class="truncate text-xs font-medium text-slate-200" title="${this.attr(e.name)}">${this.attr(e.name)}</div>
        <div class="mt-1 flex items-center gap-1">
          <button type="button" data-action="deck-builder#step" data-ygo="${e.ygo}" data-zone="${e.zone}" data-delta="-1" class="grid h-9 w-9 place-items-center rounded border border-slate-800 text-slate-300 hover:border-violet-600" aria-label="Decrease">−</button>
          <span class="w-5 text-center text-sm font-semibold">${e.qty}</span>
          <button type="button" data-action="deck-builder#step" data-ygo="${e.ygo}" data-zone="${e.zone}" data-delta="1" class="grid h-9 w-9 place-items-center rounded border border-slate-800 text-slate-300 hover:border-violet-600" aria-label="Increase">+</button>
          <button type="button" data-action="deck-builder#removeCard" data-ygo="${e.ygo}" data-zone="${e.zone}" class="ml-auto grid h-9 w-9 place-items-center rounded border border-slate-800 text-slate-500 hover:border-rose-600 hover:text-rose-300" aria-label="Remove">✕</button>
        </div>
      </div>
    </div>`
  }

  zoneEmpty(z) {
    return `<p class="col-span-full rounded-lg border border-dashed border-slate-800 px-3 py-4 text-center text-xs text-slate-600">No ${z} cards yet.</p>`
  }

  // ---- helpers ---------------------------------------------------------

  art(img, name, cls) {
    if (img) {
      return `<img src="/card_images/${img}.jpg" alt="${this.attr(name)}" loading="lazy" class="${cls} rounded-md border border-slate-800 object-cover bg-slate-900">`
    }
    const mono = (name || "?").slice(0, 2).toUpperCase()
    return `<div class="${cls} grid place-items-center rounded-md border border-slate-800 bg-slate-900 text-xs font-semibold uppercase text-slate-600">${this.attr(mono)}</div>`
  }

  flashError(msg) {
    if (!this.hasFlashTarget) return
    this.flashTarget.innerHTML = `<p class="rounded-lg border border-rose-700 bg-rose-950 px-3 py-2 text-sm text-rose-300">${this.attr(msg)}</p>`
    setTimeout(() => { if (this.hasFlashTarget) this.flashTarget.innerHTML = "" }, 4000)
  }

  csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  attr(s) {
    const d = document.createElement("div")
    d.textContent = s ?? ""
    return d.innerHTML.replaceAll('"', "&quot;")
  }
}
