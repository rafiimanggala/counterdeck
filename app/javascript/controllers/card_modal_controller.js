import { Controller } from "@hotwired/stimulus"

// Global card-detail modal. Any element with
//   data-action="card-modal#open" data-card-modal-url-param="/cards/123"
// (or data-url="/cards/123") fetches the card detail partial and shows it.
export default class extends Controller {
  static targets = ["overlay", "content"]

  connect() {
    this.onKey = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
  }

  async open(event) {
    const el = event.currentTarget
    const url = el.dataset.url || el.getAttribute("data-card-modal-url-param")
    if (!url) return
    event.preventDefault()

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
  }

  // Close only when the backdrop itself is clicked, not the panel.
  backdrop(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  show() {
    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.overlayTarget.classList.add("hidden")
    this.contentTarget.innerHTML = ""
    document.body.classList.remove("overflow-hidden")
  }
}
