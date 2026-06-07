import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Master-Duel-style two-pane deck builder. The whole local catalog is loaded
// once into memory so search/filter is instant and client-side. The LEFT pane is
// the deck, the RIGHT pane is the card database; cards are added by tapping a
// tile OR (on a fine pointer) dragging it from the database into a deck zone.
// Adding is optimistic (DOM updates immediately, the server persists in a
// debounced background POST) and the expensive matchups frame refreshes only
// after edits settle - never on the click itself.
export default class extends Controller {
  static targets = [
    "pool", "search", "main", "extra", "side", "count", "validity",
    "related", "remoteToggle", "flash", "deckPane", "poolPane", "tabBtn", "formatBtn", "saveBtn"
  ]
  static values = {
    indexUrl: String, persistUrl: String, searchUrl: String, matchupsUrl: String,
    format: { type: String, default: "tcg" }, deck: Array
  }

  EXTRA_FRAMES = ["fusion", "synchro", "xyz", "link"]
  // Banlist copy ceilings per status (total across the whole deck).
  BAN_LIMIT = { forbidden: 0, limited: 1, semi_limited: 2, unlimited: 3 }
  STAPLES = ['Maxx "C"', "Ash Blossom & Joyous Spring", "Effect Veiler", "Infinite Impermanence", "Nibiru, the Primal Being", "Called by the Grave", "Triple Tactics Talent", "Forbidden Droplet"]

  connect() {
    this.searchAll = true // search the full YGOPRODeck database by default
    this.q = ""
    this.typeFilter = ""
    this.attrFilter = ""
    this.searchTimer = null
    this.matchupTimer = null
    this.toastTimer = null
    this.matchupSeq = 0
    // Persistence state. Each card edit is auto-saved on a per-card debounce, but
    // the Save button can flush every queued write at once and retry failures.
    this.persistTimers = new Map() // key -> debounce timeout id (queued, not sent)
    this.pendingWrites = new Map() // key -> {ygo, zone, qty} latest queued payload
    this.inFlight = new Map()      // key -> promise of the in-flight POST
    this.failedWrites = new Map()  // key -> payload whose last POST failed
    this._saving = false           // an explicit Save (flush-all) is running
    this._showSaved = false        // briefly show the "Saved" confirmation state
    this._lastSaveState = null      // last painted save state (skips redundant repaints)
    this.index = []
    this.banByYgo = new Map()
    this.coarse = window.matchMedia("(pointer: coarse)").matches
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    // deck: Map "zone:ygo" -> {ygo, cardId, name, kind, img, zone, qty}
    this.deck = new Map()
    for (const e of this.deckValue) this.deck.set(`${e.zone}:${e.ygo}`, { ...e })

    // Delegated <img> error handler -> swap a missing thumbnail for a monogram.
    this.artErrorHandler = this.onArtError.bind(this)
    this.element.addEventListener("error", this.artErrorHandler, true)

    // The card modal lives in the layout (outside this element); its "Add"
    // buttons reach the builder through a global event.
    this.externalAdd = this.onExternalAdd.bind(this)
    window.addEventListener("counterdeck:add-to-deck", this.externalAdd)

    this.renderDeck()
    this.renderSaveStatus()
    this.loadIndex()
    if (!this.coarse) this.initDeckZones()
  }

  disconnect() {
    clearTimeout(this.searchTimer)
    clearTimeout(this.matchupTimer)
    clearTimeout(this.toastTimer)
    clearTimeout(this._savedTimer)
    for (const t of this.persistTimers.values()) clearTimeout(t)
    this.element.removeEventListener("error", this.artErrorHandler, true)
    window.removeEventListener("counterdeck:add-to-deck", this.externalAdd)
    this.deckSortables?.forEach((s) => s.destroy())
    this.poolSortable?.destroy()
    this.relatedSortable?.destroy()
  }

  // The card-detail modal dispatched an add request (the user opened a card and
  // pressed "Add to deck" / "Add to side"). detail: {ygo, kind, name, zone}.
  onExternalAdd(event) {
    const { ygo, kind, name, zone } = event.detail || {}
    if (!ygo) return
    this.addCard(Number(ygo), kind || "", name || null, zone || null)
  }

  async loadIndex() {
    try {
      const res = await fetch(this.indexUrlValue, { headers: { Accept: "application/json" } })
      if (res.ok) {
        this.index = await res.json()
        // ygo -> { tcg?, md? } restricted-status map (unlimited cards omitted server-side)
        this.banByYgo = new Map()
        for (const c of this.index) {
          const ygo = c.ygo_id ?? c.ygo
          if (c.ban) this.banByYgo.set(ygo, c.ban)
        }
        this.runSearch() // paint the related strip + initial browse now that we have data
      }
    } catch { /* search still works once the index loads; ignore */ }
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
      el.setAttribute("aria-pressed", String(on))
    })
  }

  async toggleRemote(event) {
    this.searchAll = event.currentTarget.checked
    await this.runSearch()
  }

  // ---- banlist format (TCG / MD) ---------------------------------------

  // The banlist follows the chosen format: copy limits, the tile badges and the
  // matchup tiers (a forbidden out is demoted) all key off this.formatValue.
  setFormat(event) {
    const f = event.currentTarget.dataset.format
    if (!["tcg", "md"].includes(f) || f === this.formatValue) return
    this.formatValue = f
    this.formatBtnTargets.forEach((b) => {
      const on = b.dataset.format === f
      b.classList.toggle("bg-violet-600", on)
      b.classList.toggle("text-white", on)
      b.classList.toggle("text-slate-400", !on)
      b.setAttribute("aria-pressed", String(on))
    })
    this.renderDeck()       // repaint deck badges + legality line
    this.runSearch()        // repaint pool badges
    this.scheduleMatchups() // re-tier outs against the new banlist
  }

  formatLabel() {
    return this.formatValue === "md" ? "Master Duel" : "TCG"
  }

  banStatus(ygo) {
    return this.banByYgo?.get(ygo)?.[this.formatValue] || "unlimited"
  }

  banLimit(ygo) {
    return this.BAN_LIMIT[this.banStatus(ygo)] ?? 3
  }

  // MD-Meta-style corner disc: red bar = Forbidden, amber "1" = Limited,
  // yellow "2" = Semi-Limited. Nothing for unlimited. Matches BanlistHelper#ban_icon.
  BAN_DISC = { forbidden: "#dc2626", limited: "#f59e0b", semi_limited: "#facc15" }
  BAN_NAME = { forbidden: "Forbidden", limited: "Limited (1 copy)", semi_limited: "Semi-Limited (2 copies)" }

  banSvg(st) {
    const disc = this.BAN_DISC[st]
    if (!disc) return ""
    const inner = st === "forbidden"
      ? `<rect x="4" y="14.5" width="24" height="3" rx="1.5" fill="#fff"/>`
      : `<text x="16" y="22.5" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif" font-size="17" font-weight="800" fill="#1c1917">${st === "limited" ? "1" : "2"}</text>`
    return `<svg viewBox="0 0 32 32" width="18" height="18" class="drop-shadow" aria-hidden="true"><circle cx="16" cy="16" r="15" fill="${disc}" stroke="rgba(0,0,0,.4)" stroke-width="1.5"/>${inner}</svg>`
  }

  banBadge(ygo) {
    const st = this.banStatus(ygo)
    if (!this.BAN_DISC[st]) return ""
    return `<span class="pointer-events-none absolute right-1 top-1 z-10 block h-[18px] w-[18px]" title="${this.attr(this.BAN_NAME[st])} in ${this.attr(this.formatLabel())}">${this.banSvg(st)}</span>`
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

  // Archetype-mates of what's in the deck, then staples. Shown in the Related strip.
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
      if (out.length >= 15) break
    }
    if (out.length < 15) {
      const names = new Set(this.STAPLES)
      for (const c of this.index) {
        if (names.has(c.name) && !owned.has(c.ygo_id) && !seen.has(c.ygo_id)) { out.push(c); seen.add(c.ygo_id) }
      }
    }
    return out.slice(0, 15)
  }

  async runSearch() {
    const hasQuery = this.q.length >= 1 || this.typeFilter || this.attrFilter
    let results

    if (hasQuery) {
      results = this.index.filter((c) => {
        if (this.q && !(c.name || "").toLowerCase().includes(this.q)) return false
        return this.matchesFilters(c)
      })
      if (this.searchAll && this.q.length >= 2) results = await this.augmentRemote(results)
    } else {
      results = this.index // browse the whole database
    }

    this.renderPool(results, hasQuery)
  }

  // Fold in full-database (YGOPRODeck) name matches the local catalog lacks.
  async augmentRemote(results) {
    try {
      const res = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(this.q)}`, { headers: { Accept: "application/json" } })
      if (!res.ok) return results
      const have = new Set(results.map((r) => r.ygo_id ?? r.ygo))
      for (const r of await res.json()) {
        if (have.has(r.ygo_id)) continue
        const row = { ygo_id: r.ygo_id, name: r.name, kind: r.kind, attr: null, img: r.image }
        // Remote rows carry no attribute, so an active attribute filter excludes
        // them (we can't confirm a match) - but the type filter still applies.
        if (this.matchesFilters(row)) results.push(row)
      }
    } catch { /* keep local results */ }
    return results
  }

  // ---- rendering: database pane ---------------------------------------

  renderRelated() {
    if (!this.hasRelatedTarget) return
    const items = this.suggestions()
    if (!items.length) { this.relatedTarget.innerHTML = ""; this.relatedSortable?.destroy(); this.relatedSortable = null; return }
    const label = this.deck.size ? "Related to your deck" : "Staples to start with"
    this.relatedTarget.innerHTML = `
      <div class="mb-3 rounded-r-lg border-l-2 border-violet-500/40 bg-violet-500/[0.03] py-2 pl-2 pr-1">
        <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-violet-300/80">${label}</p>
        <div data-related-grid class="grid grid-cols-[repeat(auto-fill,minmax(6rem,1fr))] gap-1.5">${items.map((c) => this.poolTile(c)).join("")}</div>
      </div>`
    this.initRelatedSortable()
  }

  renderPool(cards, hasQuery) {
    if (hasQuery) {
      if (this.hasRelatedTarget) this.relatedTarget.innerHTML = ""
      this.relatedSortable?.destroy()
      this.relatedSortable = null
    } else {
      this.renderRelated()
    }

    const shown = cards.slice(0, 60)
    if (!shown.length) {
      this.poolTarget.innerHTML = hasQuery
        ? `<p class="col-span-full py-8 text-center text-sm text-slate-600">No cards match.</p>`
        : ""
    } else {
      const more = cards.length > shown.length
        ? `<p class="col-span-full pt-2 text-center text-xs text-slate-600">Showing ${shown.length} of ${cards.length} - search to narrow.</p>`
        : ""
      this.poolTarget.innerHTML = shown.map((c) => this.poolTile(c)).join("") + more
    }
    this.initPoolSortable()
  }

  poolTile(c) {
    const ygo = c.ygo_id ?? c.ygo
    const imgId = c.img ?? ygo
    const name = this.attr(c.name)
    const kind = this.attr(c.kind)
    const owned = this.ownedQty(ygo)
    const badge = owned
      ? `<span class="pointer-events-none absolute left-1 top-1 z-10 inline-flex items-center gap-0.5 rounded bg-emerald-600 px-1 text-[10px] font-bold text-white shadow">&#10003;${owned > 1 ? owned : ""}</span>`
      : ""
    // Touch: a solid, always-visible Add bar (no hover to reveal it); tapping the
    // card art still opens the detail modal. Fine pointer: a translucent strip
    // that fades in on hover, and the .pool-card can be dragged into a deck zone.
    const quickAdd = this.coarse
      ? `<button type="button" data-action="deck-builder#add" data-ygo="${ygo}" data-kind="${kind}" data-name="${name}" aria-label="Add ${name} to deck"
          class="absolute inset-x-0 bottom-0 z-10 flex h-8 items-center justify-center gap-1 rounded-b-lg bg-violet-600 text-xs font-semibold text-white shadow-sm active:bg-violet-500 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-violet-300">+ Add</button>`
      : `<button type="button" data-action="deck-builder#add" data-ygo="${ygo}" data-kind="${kind}" data-name="${name}" aria-label="Add ${name} to deck"
          class="absolute inset-x-0 bottom-0 z-10 flex h-7 items-center justify-center gap-1 rounded-b-lg border-t border-violet-500/40 bg-slate-950/85 text-xs font-semibold text-violet-200 opacity-0 backdrop-blur-sm transition group-hover:opacity-100 focus:opacity-100 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-violet-400">+ Add</button>`
    return `<div class="pool-card group relative" data-ygo="${ygo}" data-kind="${kind}" data-name="${name}" title="${name}">
      <button type="button" data-action="card-modal#open" data-url="/cards/${ygo}?builder=1" aria-label="${name} details"
        class="block w-full overflow-hidden rounded-lg border ${owned ? "border-emerald-600/70" : "border-slate-800"} bg-slate-900 transition hover:border-violet-500 focus:border-violet-500 focus:outline-none">
        ${this.art(imgId, c.name, "aspect-[59/86] w-full")}
      </button>
      ${badge}
      ${this.banBadge(ygo)}
      ${quickAdd}
    </div>`
  }

  // ---- add / adjust / remove (optimistic) ------------------------------

  add(event) {
    // Keep the quick-add click from bubbling to the card-face modal trigger or
    // tripping Sortable's drag detection on the surrounding .pool-card.
    event.preventDefault()
    event.stopPropagation()
    const { ygo, kind, name } = event.currentTarget.dataset
    this.addCard(Number(ygo), kind || "", name || null)
  }

  addCard(ygo, kind, name = null, desiredZone = null) {
    // The active banlist caps how many copies (total, across every zone) may run.
    const limit = this.banLimit(ygo)
    if (this.ownedQty(ygo) >= limit) {
      this.toast(limit === 0 ? `Forbidden in ${this.formatLabel()}` : `Limited to ${limit} in ${this.formatLabel()}`)
      return
    }
    const card = this.lookup(ygo) || { ygo, name, kind, img: null }
    const k = card.kind || kind
    const zone = this.resolveZone(k, desiredZone || this.zoneFor(k))
    if (desiredZone && zone !== desiredZone) this.toast(`Moved to ${zone} deck`)

    const key = `${zone}:${ygo}`
    const existing = this.deck.get(key)
    const qty = Math.min((existing?.qty || 0) + 1, 3)
    this.deck.set(key, { ygo, cardId: existing?.cardId, name: card.name || name, kind: k, img: card.img ?? existing?.img, zone, qty })
    this.renderDeck()
    this.persist(ygo, zone, qty)
  }

  step(event) {
    const { ygo, zone, delta } = event.currentTarget.dataset
    const key = `${zone}:${Number(ygo)}`
    const entry = this.deck.get(key)
    if (!entry) return
    const qty = Math.min(Math.max(entry.qty + Number(delta), 0), 3)
    if (qty === 0) this.deck.delete(key)
    else entry.qty = qty
    this.renderDeck()
    this.persist(Number(ygo), zone, qty)
  }

  // Tap/keyboard path for re-zoning a SINGLE copy between its natural zone and
  // the side deck (drag is the mouse equivalent, also one copy at a time).
  sideOne(event) {
    const { ygo, zone, kind } = event.currentTarget.dataset
    const to = zone === "side" ? this.zoneFor(kind) : "side"
    this.moveOneCopy(Number(ygo), zone, to, kind)
  }

  // Move exactly one copy of a card from one zone to another. An illegal target
  // (e.g. a Main monster dropped on Extra) resolves back to a legal zone; if
  // that equals the source it is a no-op.
  moveOneCopy(ygo, fromZone, toZone, kind) {
    const finalZone = this.resolveZone(kind, toZone)
    if (!fromZone || finalZone === fromZone) { this.renderDeck(); return }
    if (finalZone !== toZone) this.toast(`Moved to ${finalZone} deck`)
    const fromKey = `${fromZone}:${ygo}`
    const fromEntry = this.deck.get(fromKey)
    if (!fromEntry) { this.renderDeck(); return }

    const fromQty = fromEntry.qty - 1
    if (fromQty <= 0) this.deck.delete(fromKey)
    else fromEntry.qty = fromQty

    const toKey = `${finalZone}:${ygo}`
    const toExisting = this.deck.get(toKey)
    const toQty = Math.min((toExisting?.qty || 0) + 1, 3)
    this.deck.set(toKey, { ygo, cardId: fromEntry.cardId, name: fromEntry.name, kind, img: fromEntry.img, zone: finalZone, qty: toQty })

    this.renderDeck()
    this.persist(ygo, fromZone, fromQty <= 0 ? 0 : fromQty)
    this.persist(ygo, finalZone, toQty)
  }

  // ---- zone routing ----------------------------------------------------

  isExtraKind(kind) {
    const k = (kind || "").toLowerCase()
    return this.EXTRA_FRAMES.some((f) => k.includes(f))
  }

  zoneFor(kind) {
    return this.isExtraKind(kind) ? "extra" : "main"
  }

  // A card can sit in its natural zone or the side deck; anything else snaps back.
  resolveZone(kind, desired) {
    const legal = this.isExtraKind(kind) ? ["extra", "side"] : ["main", "side"]
    return legal.includes(desired) ? desired : (this.isExtraKind(kind) ? "extra" : "main")
  }

  zoneOfEl(el) {
    if (this.hasMainTarget && el === this.mainTarget) return "main"
    if (this.hasExtraTarget && el === this.extraTarget) return "extra"
    if (this.hasSideTarget && el === this.sideTarget) return "side"
    return null
  }

  lookup(ygo) {
    return this.index.find((c) => (c.ygo_id ?? c.ygo) === ygo)
  }

  ownedQty(ygo) {
    let n = 0
    for (const e of this.deck.values()) if (e.ygo === ygo) n += e.qty
    return n
  }

  // ---- drag and drop (fine pointers only) ------------------------------

  // Shared config for any card source (the pool AND the related/staples strip):
  // a clone source you can drag from but not drop into. Card faces are <img>,
  // which the browser drags natively (draggable=true); that hijacks native HTML5
  // DnD, so forceFallback uses mouse events instead and the whole tile drags
  // reliably. fallbackTolerance keeps a plain click (open the modal) from reading
  // as a drag.
  cardSourceConfig() {
    return {
      group: { name: "cards", pull: "clone", put: false },
      sort: false,
      draggable: ".pool-card",
      forceFallback: true,
      supportPointer: false,
      fallbackTolerance: 5,
      fallbackOnBody: true,
      animation: this.reducedMotion ? 0 : 150,
      ghostClass: "opacity-40",
      onStart: (e) => this.highlightZones(true, e.item.dataset.kind),
      onEnd: () => this.highlightZones(false)
    }
  }

  initPoolSortable() {
    if (this.coarse || !this.hasPoolTarget) return
    this.poolSortable?.destroy()
    this.poolSortable = Sortable.create(this.poolTarget, this.cardSourceConfig())
    this.poolTarget.dataset.sortable = "ready"
  }

  // The "Related / Staples" strip is also a draggable clone source.
  initRelatedSortable() {
    this.relatedSortable?.destroy()
    this.relatedSortable = null
    if (this.coarse || !this.hasRelatedTarget) return
    const grid = this.relatedTarget.querySelector("[data-related-grid]")
    if (!grid) return
    this.relatedSortable = Sortable.create(grid, this.cardSourceConfig())
  }

  initDeckZones() {
    this.deckSortables?.forEach((s) => s.destroy())
    this.deckSortables = ["main", "extra", "side"].map((z) => {
      const el = this[`${z}Target`]
      if (!el) return null
      return Sortable.create(el, {
        group: { name: "cards", pull: true, put: true },
        handle: ".drag-handle",
        draggable: ".deck-card",
        forceFallback: true,
        supportPointer: false,
        fallbackTolerance: 5,
        fallbackOnBody: true,
        animation: this.reducedMotion ? 0 : 150,
        ghostClass: "opacity-40",
        onStart: (e) => this.highlightZones(true, e.item.dataset.kind),
        onEnd: () => this.highlightZones(false),
        onAdd: (e) => this.onDropIntoZone(e, z)
      })
    }).filter(Boolean)
    this.element.dataset.deckZonesReady = String(this.deckSortables.length)
  }

  onDropIntoZone(event, zoneName) {
    const item = event.item
    const ygo = Number(item.dataset.ygo)
    const kind = item.dataset.kind || ""
    const name = item.dataset.name || null
    // A deck zone source means a re-zone; anything else (the pool OR the
    // related/staples strip) is a fresh add.
    const fromZone = this.zoneOfEl(event.from)
    item.remove() // the Map + renderDeck is the single source of truth
    if (!ygo) { this.renderDeck(); return }
    if (fromZone) this.moveOneCopy(ygo, fromZone, zoneName, kind)
    else this.addCard(ygo, kind, name, zoneName)
  }

  highlightZones(on, kind) {
    const legal = on ? (this.isExtraKind(kind || "") ? ["extra", "side"] : ["main", "side"]) : []
    for (const z of ["main", "extra", "side"]) {
      const el = this[`${z}Target`]
      if (!el) continue
      const ok = legal.includes(z)
      el.classList.toggle("ring-1", on && ok)
      el.classList.toggle("ring-violet-500/60", on && ok)
      el.classList.toggle("bg-violet-500/5", on && ok)
      el.classList.toggle("opacity-40", on && !ok)
    }
  }

  // ---- tab toggle (mobile pane switcher) -------------------------------

  setTab(event) {
    const tab = event.currentTarget.dataset.tab // "deck" | "add"
    this.tabBtnTargets.forEach((b) => {
      const on = b.dataset.tab === tab
      b.classList.toggle("bg-slate-800", on)
      b.classList.toggle("text-slate-100", on)
      b.classList.toggle("text-slate-500", !on)
      b.setAttribute("aria-pressed", String(on))
    })
    if (this.hasDeckPaneTarget) this.deckPaneTarget.classList.toggle("hidden", tab !== "deck")
    if (this.hasPoolPaneTarget) this.poolPaneTarget.classList.toggle("hidden", tab !== "add")
  }

  // ---- rendering: deck pane -------------------------------------------

  renderDeck() {
    const zones = { main: [], extra: [], side: [] }
    for (const e of this.deck.values()) zones[e.zone]?.push(e)

    for (const z of ["main", "extra", "side"]) {
      const target = this[`${z}Target`]
      if (!target) continue
      const list = zones[z].sort((a, b) => (a.name || "").localeCompare(b.name || ""))
      // Master-Duel-style: every copy is its own card face (3-of => three faces),
      // packed in a tight auto-fill grid.
      target.className = "grid min-h-[64px] grid-cols-[repeat(auto-fill,minmax(4.5rem,1fr))] gap-1.5 rounded-xl border border-transparent p-1"
      const tiles = []
      for (const e of list) for (let i = 0; i < e.qty; i++) tiles.push(this.deckTile(e))
      target.innerHTML = tiles.length ? tiles.join("") : this.zoneEmpty(z)
    }
    this.renderCounts()
  }

  renderCounts() {
    const sum = (z) => [...this.deck.values()].filter((e) => e.zone === z).reduce((n, e) => n + e.qty, 0)
    const main = sum("main"), extra = sum("extra"), side = sum("side")

    if (this.hasCountTarget) {
      const pill = (label, n, ok) =>
        `<span class="inline-flex items-center gap-1 rounded-md border border-slate-800 bg-slate-900 px-2 py-1 text-xs"><span class="text-slate-500">${label}</span><span class="font-semibold ${ok ? "text-emerald-400" : "text-rose-400"}">${n}</span></span>`
      this.countTarget.innerHTML =
        pill("MAIN", main, main >= 40 && main <= 60) +
        pill("EXTRA", extra, extra <= 15) +
        pill("SIDE", side, side <= 15)
    }

    if (this.hasValidityTarget) {
      const banBroken = this.banlistViolations()
      let msg, cls
      if (main < 40) { msg = `Add ${40 - main} more main-deck card${40 - main !== 1 ? "s" : ""} to be tournament-legal`; cls = "text-amber-400" }
      else if (main > 60) { msg = `Main deck is ${main} cards (max 60)`; cls = "text-rose-400" }
      else if (extra > 15) { msg = "Extra deck over 15 cards"; cls = "text-rose-400" }
      else if (side > 15) { msg = "Side deck over 15 cards"; cls = "text-rose-400" }
      else if (banBroken > 0) { msg = `${banBroken} card${banBroken !== 1 ? "s" : ""} over the ${this.formatLabel()} banlist`; cls = "text-rose-400" }
      else { msg = `Tournament-legal · ${this.formatLabel()}`; cls = "text-emerald-400" }
      this.validityTarget.textContent = msg
      this.validityTarget.className = `text-xs font-medium ${cls}`
    }
  }

  // Distinct cards whose total copies exceed the active format's banlist limit.
  banlistViolations() {
    let n = 0
    for (const ygo of new Set([...this.deck.values()].map((e) => e.ygo))) {
      if (this.ownedQty(ygo) > this.banLimit(ygo)) n++
    }
    return n
  }

  // One copy = one card face (Master-Duel style). Clicking the face opens the
  // detail modal; a hover strip (always shown on touch) removes that copy or
  // sends it to/from the side deck. On a fine pointer the face is the drag
  // handle for moving a single copy between zones.
  deckTile(e) {
    const imgId = e.img ?? e.ygo
    const name = this.attr(e.name)
    const kind = this.attr(e.kind)
    const inSide = e.zone === "side"
    const dragCls = this.coarse ? "" : " drag-handle cursor-grab"
    const ctlVis = this.coarse ? "opacity-100" : "opacity-0 transition group-hover:opacity-100 group-focus-within:opacity-100"
    // Flag a copy that pushes this card over its banlist limit for the format.
    const over = this.ownedQty(e.ygo) > this.banLimit(e.ygo)
    const borderCls = over ? "border-rose-500/70" : "border-slate-800"
    return `<div class="deck-card group relative" data-ygo="${e.ygo}" data-zone="${e.zone}" data-kind="${kind}" data-name="${name}" title="${name}">
      <button type="button" data-action="card-modal#open" data-url="/cards/${e.ygo}?builder=1" aria-label="${name} details"
        class="block w-full overflow-hidden rounded-lg border ${borderCls} transition hover:border-violet-500 focus:border-violet-500 focus:outline-none${dragCls}">
        ${this.art(imgId, e.name, "aspect-[59/86] w-full")}
      </button>
      ${this.banBadge(e.ygo)}
      <div class="absolute inset-x-0 bottom-0 z-10 flex gap-px overflow-hidden rounded-b-lg ${ctlVis}">
        <button type="button" data-action="deck-builder#step" data-ygo="${e.ygo}" data-zone="${e.zone}" data-delta="-1" aria-label="Remove this copy of ${name}"
          class="grid h-6 flex-1 place-items-center bg-slate-950/85 text-slate-300 backdrop-blur-sm hover:bg-rose-600 hover:text-white focus:outline-none focus:ring-2 focus:ring-inset focus:ring-violet-400">&times;</button>
        <button type="button" data-action="deck-builder#sideOne" data-ygo="${e.ygo}" data-zone="${e.zone}" data-kind="${kind}" aria-label="${inSide ? `Move this copy of ${name} out of the side deck` : `Move this copy of ${name} to the side deck`}"
          class="grid h-6 w-7 shrink-0 place-items-center bg-slate-950/85 text-[11px] font-semibold backdrop-blur-sm hover:bg-violet-600 hover:text-white focus:outline-none focus:ring-2 focus:ring-inset focus:ring-violet-400 ${inSide ? "text-violet-300" : "text-slate-400"}">${inSide ? "M" : "S"}</button>
      </div>
    </div>`
  }

  zoneEmpty(z) {
    const hint = this.coarse ? "Find a card and tap its + Add" : "Drag a card here, or hover one and hit Add"
    return `<p class="col-span-full rounded-lg border border-dashed border-slate-800 px-3 py-4 text-center text-xs text-slate-600">No ${z} cards yet. ${hint}.</p>`
  }

  // ---- persistence (debounced per card, last-write-wins) ---------------

  // Queue a write for one card. Auto-saves after a short debounce; the latest
  // payload per card wins, so rapid quantity taps collapse to one request.
  persist(ygo, zone, qty) {
    const key = `${zone}:${ygo}`
    this.pendingWrites.set(key, { ygo, zone, qty })
    this.failedWrites.delete(key) // a fresh edit supersedes any earlier failure
    this._showSaved = false
    this.renderSaveStatus()
    clearTimeout(this.persistTimers.get(key))
    this.persistTimers.set(key, setTimeout(() => this.flushKey(key), 350))
  }

  // Send the queued write for one card immediately (cancels its debounce).
  // Returns the in-flight promise so a flush-all can await every write.
  flushKey(key) {
    clearTimeout(this.persistTimers.get(key))
    this.persistTimers.delete(key)
    if (this.inFlight.has(key)) return this.inFlight.get(key) // already sending
    const payload = this.pendingWrites.get(key)
    if (!payload) return Promise.resolve()
    this.pendingWrites.delete(key)
    const promise = this.sendWrite(key, payload)
    this.inFlight.set(key, promise)
    this.renderSaveStatus()
    return promise
  }

  async sendWrite(key, payload) {
    const body = new FormData()
    body.append("ygo_id", payload.ygo)
    body.append("zone", payload.zone)
    body.append("quantity", payload.qty)
    try {
      const res = await fetch(this.persistUrlValue, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrf() },
        body
      })
      if (res.ok) {
        const data = await res.json()
        const entry = this.deck.get(key)
        if (entry && data.ok && payload.qty > 0) {
          if (data.img && !entry.img) { entry.img = data.img; this.renderDeck() }
          if (data.card_id) entry.cardId = data.card_id
        }
        this.failedWrites.delete(key)
      } else {
        this.failedWrites.set(key, payload)
        this.flashError("Couldn't save that change.")
      }
    } catch {
      this.failedWrites.set(key, payload)
      this.flashError("Network error saving deck.")
    } finally {
      this.inFlight.delete(key)
      this.scheduleMatchups()
      if (this.allSaved()) this.flashSaved()
      else this.renderSaveStatus()
    }
  }

  // Explicit Save: flush every queued write now, retry any prior failures, and
  // confirm. Useful when the user wants certainty without waiting on debounce.
  async saveDeck() {
    if (this._saving) return // a flush is already running; ignore re-entrant clicks
    for (const [key, payload] of [...this.failedWrites]) {
      this.pendingWrites.set(key, payload)
      this.failedWrites.delete(key)
    }
    const keys = new Set([...this.pendingWrites.keys(), ...this.persistTimers.keys()])
    if (!keys.size && !this.inFlight.size) { this.flashSaved(); this.toast("All changes saved"); return }

    this._saving = true
    this.renderSaveStatus()
    const flushes = [...keys].map((key) => this.flushKey(key))
    await Promise.allSettled([...flushes, ...this.inFlight.values()])
    this._saving = false
    if (this.failedWrites.size) { this.renderSaveStatus(); this.flashError("Some changes didn't save - tap Retry.") }
    else { this.flashSaved(); this.toast("Deck saved") }
  }

  allSaved() {
    return !this.pendingWrites.size && !this.persistTimers.size && !this.inFlight.size && !this.failedWrites.size
  }

  flashSaved() {
    this._showSaved = true
    this.renderSaveStatus()
    clearTimeout(this._savedTimer)
    this._savedTimer = setTimeout(() => { this._showSaved = false; this.renderSaveStatus() }, 2000)
  }

  // Paint the Save button to reflect live save state (idle/saving/saved/error).
  renderSaveStatus() {
    if (!this.hasSaveBtnTarget) return
    const busy = this.pendingWrites.size || this.persistTimers.size || this.inFlight.size || this._saving
    let state = "idle"
    if (this.failedWrites.size) state = "error"
    else if (busy) state = "saving"
    else if (this._showSaved) state = "saved"
    if (state === this._lastSaveState) return // unchanged: skip repaint (no jank, keeps focus)
    this._lastSaveState = state

    const base = "inline-flex h-9 cursor-pointer items-center gap-1.5 rounded-lg border px-3 text-sm font-semibold transition disabled:cursor-default"
    const skin = {
      idle: "border-violet-600 bg-violet-600 text-white hover:bg-violet-500",
      saving: "border-slate-700 bg-slate-800 text-slate-400",
      saved: "border-emerald-700/50 bg-emerald-500/10 text-emerald-300",
      error: "border-rose-600 bg-rose-600 text-white hover:bg-rose-500"
    }
    const label = { idle: "Save deck", saving: "Saving…", saved: "Saved", error: "Retry save" }
    const btn = this.saveBtnTarget
    btn.className = `${base} ${skin[state]}`
    btn.disabled = state === "saving"
    btn.setAttribute("aria-busy", state === "saving" ? "true" : "false")
    btn.innerHTML = this.saveIcon(state) + `<span>${label[state]}</span>`
  }

  saveIcon(state) {
    if (state === "saving") return `<svg class="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle class="opacity-25" cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2"/><path class="opacity-90" d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`
    if (state === "saved") return `<svg class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M16.7 5.3a1 1 0 0 1 0 1.4l-7.5 7.5a1 1 0 0 1-1.4 0l-3.5-3.5a1 1 0 1 1 1.4-1.4l2.79 2.79 6.8-6.79a1 1 0 0 1 1.4 0Z" clip-rule="evenodd"/></svg>`
    if (state === "error") return `<svg class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M8.49 2.6a1.73 1.73 0 0 1 3.02 0l6.3 11.25A1.73 1.73 0 0 1 16.3 16.5H3.7a1.73 1.73 0 0 1-1.51-2.65L8.49 2.6ZM10 7a1 1 0 0 0-1 1v3a1 1 0 1 0 2 0V8a1 1 0 0 0-1-1Zm0 7.5a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z" clip-rule="evenodd"/></svg>`
    return `<svg class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path d="M4 3a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V6.41a1 1 0 0 0-.29-.7l-2.42-2.42a1 1 0 0 0-.7-.29H4Zm2 1h6v3H6V4Zm4 11a3 3 0 1 1 0-6 3 3 0 0 1 0 6Z"/></svg>`
  }

  scheduleMatchups() {
    clearTimeout(this.matchupTimer)
    this.matchupTimer = setTimeout(() => {
      const frame = document.getElementById("matchups")
      // A turbo-frame only reloads when src actually changes, so use a strictly
      // monotonic token - deck.size is unchanged by a quantity step or a swap.
      if (frame) frame.src = `${this.matchupsUrlValue}?banlist=${this.formatValue}&t=${++this.matchupSeq}`
    }, 600)
  }

  // ---- helpers ---------------------------------------------------------

  // Self-hosted thumbnail by image id (falls back to the passcode). A 404 is
  // swapped for a monogram by onArtError (delegated, so it survives re-renders).
  art(imgId, name, cls) {
    const mono = this.attr((name || "?").slice(0, 2).toUpperCase())
    return `<img src="/card_images/${imgId}.jpg" alt="${this.attr(name)}" loading="lazy" data-art="1" data-mono="${mono}" class="${cls} rounded-md border border-slate-800 bg-slate-900 object-cover">`
  }

  onArtError(event) {
    const img = event.target
    if (img.tagName !== "IMG" || img.dataset.art !== "1" || img.dataset.fellback) return
    img.dataset.fellback = "1"
    const div = document.createElement("div")
    div.className = `${img.className} grid place-items-center text-xs font-semibold uppercase text-slate-600`
    div.textContent = img.dataset.mono || "?"
    div.setAttribute("role", "img")
    div.setAttribute("aria-label", img.alt || img.dataset.mono || "Card")
    img.replaceWith(div)
  }

  toast(msg) {
    if (!this.hasFlashTarget) return
    this.flashTarget.innerHTML = `<p class="rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-xs text-slate-300">${this.attr(msg)}</p>`
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => { if (this.hasFlashTarget) this.flashTarget.innerHTML = "" }, 1400)
  }

  flashError(msg) {
    if (!this.hasFlashTarget) return
    this.flashTarget.innerHTML = `<p class="rounded-lg border border-rose-700 bg-rose-950 px-3 py-2 text-sm text-rose-300">${this.attr(msg)}</p>`
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => { if (this.hasFlashTarget) this.flashTarget.innerHTML = "" }, 4000)
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
