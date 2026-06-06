import { Controller } from "@hotwired/stimulus"

// Adds/removes nested counter-recommendation rows in the admin deck form.
// Usage: data-controller="nested-form" with a <template data-nested-form-target="template">
// holding one blank row (child_index "NEW_RECORD") and a container
// data-nested-form-target="rows".
export default class extends Controller {
  static targets = ["template", "rows"]

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now().toString())
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-nested-form-row]")
    if (!row) return
    const destroyInput = row.querySelector("input[name*='_destroy']")
    if (destroyInput) {
      destroyInput.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
  }
}
