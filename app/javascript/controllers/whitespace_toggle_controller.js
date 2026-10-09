import { Controller } from "@hotwired/stimulus"

const KEY = "ocl-i18n.show-whitespace"

// Reveals spaces and line breaks in the i18n-text views (html.show-ws), remembered per browser
export default class extends Controller {
  connect() {
    let on = false
    try { on = localStorage.getItem(KEY) === "1" } catch {}
    this.apply(on)
  }

  toggle() {
    const on = !document.documentElement.classList.contains("show-ws")
    try { localStorage.setItem(KEY, on ? "1" : "0") } catch {}
    this.apply(on)
  }

  apply(on) {
    document.documentElement.classList.toggle("show-ws", on)
    this.element.setAttribute("aria-pressed", on)
  }
}
