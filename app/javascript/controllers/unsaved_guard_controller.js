import { Controller } from "@hotwired/stimulus"

// Guards the page's unsaved edits (forms flagged `data-dirty` by dirty-form) : asks before leaving
// through a Turbo visit, a form submission that navigates, or an unload ; counts them in the optional
// `count` target, which scrolls to the first one.
export default class extends Controller {
  static targets = ["count"]
  static values = { message: String, labels: Object }

  connect() {
    this.refresh = this.refresh.bind(this)
    this.beforeUnload = this.beforeUnload.bind(this)
    this.beforeVisit = this.beforeVisit.bind(this)
    this.submit = this.submit.bind(this)
    addEventListener("dirty-form:change", this.refresh)
    addEventListener("beforeunload", this.beforeUnload)
    addEventListener("turbo:before-visit", this.beforeVisit)
    // Capture : runs before Turbo, which drops submissions whose default is prevented
    addEventListener("submit", this.submit, true)
    this.refresh()
  }

  disconnect() {
    removeEventListener("dirty-form:change", this.refresh)
    removeEventListener("beforeunload", this.beforeUnload)
    removeEventListener("turbo:before-visit", this.beforeVisit)
    removeEventListener("submit", this.submit, true)
  }

  dirtyForms() {
    return [...document.querySelectorAll("form[data-dirty]")]
  }

  refresh() {
    if (!this.hasCountTarget) return
    const count = this.dirtyForms().length
    const rule = new Intl.PluralRules(document.documentElement.lang).select(count)
    this.countTarget.textContent = (this.labelsValue[rule] ?? this.labelsValue.other ?? "").replace("%{count}", count)
    this.countTarget.hidden = count === 0
  }

  reveal() {
    const form = this.dirtyForms()[0]
    if (!form) return
    form.scrollIntoView({ block: "center" })
    form.querySelector(".cm-content, textarea:not([hidden]), input:not([type=hidden])")?.focus({ preventScroll: true })
  }

  beforeUnload(event) {
    if (this.leaving || this.dirtyForms().length === 0) return
    event.preventDefault()
    event.returnValue = ""
  }

  beforeVisit(event) {
    if (this.leaving || this.dirtyForms().length === 0) return
    if (confirm(this.messageValue)) this.leaving = true
    else event.preventDefault()
  }

  // A save rendered in its own frame keeps the page ; any other submission leaves it. The form being
  // submitted doesn't count : its edits go with it. `leaving` covers the redirect's visit that follows
  // (the new page's body brings a fresh controller).
  submit(event) {
    const form = event.target
    if (this.leaving || staysOnPage(form, event.submitter)) return
    if (this.dirtyForms().some((f) => f !== form) && !confirm(this.messageValue)) event.preventDefault()
    else this.leaving = true
  }
}

function staysOnPage(form, submitter) {
  if (form.closest("[data-turbo=false]") || submitter?.dataset.turbo === "false") return false
  const target = submitter?.dataset.turboFrame || form.dataset.turboFrame
  if (target) return target !== "_top"
  const frame = form.closest("turbo-frame")
  return !!frame && frame.getAttribute("target") !== "_top"
}
