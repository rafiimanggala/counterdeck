import { Controller } from "@hotwired/stimulus"

// Global card-detail modal. Any element with
//   data-action="card-modal#open" data-url="/cards/123"
// fetches the card detail partial and shows it in an accessible dialog
// (Escape to close, focus trapped while open, focus restored on close).
export default class extends Controller {
  static targets = ["overlay", "content"]

  connect() {
    this.onKey = (e) => {
      if (!this.isOpen()) return
      if (e.key === "Escape") this.close()
      else if (e.key === "Tab") this.trapTab(e)
    }
    document.addEventListener("keydown", this.onKey)
    // The deck-builder's image-error handler doesn't reach the modal (it lives
    // in the layout body), so swap broken card art for a monogram here too.
    this.onImgError = this.handleImgError.bind(this)
    this.contentTarget.addEventListener("error", this.onImgError, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    this.contentTarget.removeEventListener("error", this.onImgError, true)
  }

  isOpen() {
    return !this.overlayTarget.classList.contains("hidden")
  }

  async open(event) {
    const el = event.currentTarget
    const url = el.dataset.url || el.getAttribute("data-card-modal-url-param")
    if (!url) return
    event.preventDefault()
    this.returnFocusEl = el // restore focus here when the dialog closes

    this.contentTarget.innerHTML = `<div class="grid h-40 place-items-center text-sm text-slate-500">Loading…</div>`
    this.show()
    try {
      const res = await fetch(url, { headers: { Accept: "text/html" } })
      this.contentTarget.innerHTML = res.ok
        ? await res.text()
        : `<div class="grid h-40 place-items-center text-sm text-rose-400">Couldn't load that card.</div>`
    } catch {
      this.contentTarget.innerHTML = `<div class="grid h-40 place-items-center text-sm text-rose-400">Network error.</div>`
    }
    this.focusFirst()
  }

  // An "Add to deck" / "Add to side" button inside the detail panel. The deck
  // builder lives in a different part of the DOM, so we hand it the request via
  // a global event, then close.
  requestAdd(event) {
    const { ygo, kind, name, zone } = event.currentTarget.dataset
    if (!ygo) return
    window.dispatchEvent(new CustomEvent("counterdeck:add-to-deck", {
      detail: { ygo: Number(ygo), kind: kind || "", name: name || null, zone: zone || null }
    }))
    this.close()
  }

  // Close only when the backdrop itself is clicked, not the panel.
  backdrop(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  handleImgError(event) {
    const img = event.target
    if (img.tagName !== "IMG" || img.dataset.art !== "1" || img.dataset.fellback) return
    img.dataset.fellback = "1"
    const div = document.createElement("div")
    div.className = `${img.className} grid place-items-center text-lg font-semibold uppercase text-slate-600`
    div.textContent = img.dataset.mono || "?"
    div.setAttribute("role", "img")
    div.setAttribute("aria-label", img.alt || img.dataset.mono || "Card")
    img.replaceWith(div)
  }

  // ---- focus management ------------------------------------------------

  focusables() {
    const sel = 'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])'
    return [...this.overlayTarget.querySelectorAll(sel)].filter((el) => el.offsetParent !== null)
  }

  focusFirst() {
    const f = this.focusables()
    ;(f[0] || this.overlayTarget).focus?.()
  }

  trapTab(event) {
    const f = this.focusables()
    if (!f.length) return
    const first = f[0], last = f[f.length - 1]
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
  }

  show() {
    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.overlayTarget.classList.add("hidden")
    this.contentTarget.innerHTML = ""
    document.body.classList.remove("overflow-hidden")
    this.returnFocusEl?.focus?.()
    this.returnFocusEl = null
  }
}
