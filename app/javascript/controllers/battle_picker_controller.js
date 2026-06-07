import { Controller } from "@hotwired/stimulus"

// Filters the enemy meta-deck list in the Real Battle picker as you type, so you
// can find an opponent quickly without leaving the dropdown.
export default class extends Controller {
  static targets = ["query", "item", "empty"]

  connect() {
    this.queryTarget?.focus()
  }

  filter() {
    const q = this.queryTarget.value.trim().toLowerCase()
    let shown = 0
    for (const el of this.itemTargets) {
      const hit = !q || (el.dataset.name || "").toLowerCase().includes(q)
      el.hidden = !hit
      if (hit) shown++
    }
    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
  }
}
