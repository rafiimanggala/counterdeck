import { Controller } from "@hotwired/stimulus"

// Deck-builder card search. Debounced lookup against /cards/search (local catalog
// + full YGOPRODeck DB), renders a results dropdown, and adds the chosen card by
// POSTing to the deck-entries endpoint and applying the returned Turbo Stream.
export default class extends Controller {
  static targets = ["input", "results", "zone"]
  static values = { url: String, addUrl: String }

  connect() {
    this.timer = null
    this.onDocClick = (e) => { if (!this.element.contains(e.target)) this.hide() }
    document.addEventListener("click", this.onDocClick)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocClick)
    if (this.timer) clearTimeout(this.timer)
  }

  search() {
    if (this.timer) clearTimeout(this.timer)
    const q = this.inputTarget.value.trim()
    if (q.length < 2) return this.hide()
    this.timer = setTimeout(() => this.fetchResults(q), 250)
  }

  async fetchResults(q) {
    try {
      const res = await fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, {
        headers: { Accept: "application/json" },
      })
      if (!res.ok) return this.hide()
      this.render(await res.json())
    } catch {
      this.hide()
    }
  }

  render(cards) {
    if (!cards.length) {
      this.resultsTarget.innerHTML = `<div class="px-3 py-3 text-sm text-slate-500">No cards found.</div>`
      this.show()
      return
    }
    this.resultsTarget.innerHTML = cards
      .map((c) => {
        const tag = c.in_catalog
          ? ""
          : `<span class="ml-2 shrink-0 rounded bg-slate-800 px-1.5 py-0.5 text-[10px] text-slate-400">fetch</span>`
        const sub = [c.kind, c.archetype].filter(Boolean).join(" · ")
        return `<button type="button" data-action="card-search#add" data-ygo-id="${c.ygo_id}"
            class="flex w-full items-center gap-2 border-b border-slate-900 px-3 py-2 text-left hover:bg-slate-900">
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm text-slate-100">${this.esc(c.name)}</span>
              ${sub ? `<span class="block truncate text-xs text-slate-500">${this.esc(sub)}</span>` : ""}
            </span>${tag}
          </button>`
      })
      .join("")
    this.show()
  }

  async add(event) {
    const ygoId = event.currentTarget.dataset.ygoId
    const body = new FormData()
    body.append("ygo_id", ygoId)
    body.append("zone", this.selectedZone())
    const res = await fetch(this.addUrlValue, {
      method: "POST",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": this.csrfToken(),
      },
      body,
    })
    if (res.ok) {
      const html = await res.text()
      window.Turbo.renderStreamMessage(html)
      this.inputTarget.value = ""
      this.hide()
      this.inputTarget.focus()
    }
  }

  nav(event) {
    if (event.key === "Escape") this.hide()
  }

  selectedZone() {
    const checked = this.zoneTargets.find((z) => z.checked)
    return checked ? checked.value : "main"
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  esc(s) {
    const d = document.createElement("div")
    d.textContent = s ?? ""
    return d.innerHTML
  }

  show() { this.resultsTarget.classList.remove("hidden") }
  hide() { this.resultsTarget.classList.add("hidden") }
}
