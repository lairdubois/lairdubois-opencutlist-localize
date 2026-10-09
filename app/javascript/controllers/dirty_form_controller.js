import { Controller } from "@hotwired/stimulus"

// Flags the form `data-dirty` while a field differs from what the server rendered. The DOM keeps it
// (defaultValue, defaultChecked, defaultSelected), so a form re-rendered after a save starts clean.
// Changes are announced on window for unsaved-guard. Fields with `data-dirty-ignore` don't count.
// ⌘/Ctrl+Enter in a textarea submits the form (the i18n-text editor has its own binding).
// `submit` targets are disabled while the form is clean, and the form then refuses a submission through
// them or without a submitter (keyboard shortcuts go through requestSubmit(), which ignores disabled
// buttons). Other buttons (e.g. save and approve) still submit a clean form.
export default class extends Controller {
  static targets = ["submit"]

  connect() {
    this.update = this.update.bind(this)
    this.keydown = this.keydown.bind(this)
    this.submit = this.submit.bind(this)
    // i18n-text:change : the CodeMirror editor writes its hidden textarea without firing `input`
    for (const type of ["input", "change", "i18n-text:change"]) this.element.addEventListener(type, this.update)
    this.element.addEventListener("keydown", this.keydown)
    this.element.addEventListener("submit", this.submit)
    this.update()
  }

  disconnect() {
    for (const type of ["input", "change", "i18n-text:change"]) this.element.removeEventListener(type, this.update)
    this.element.removeEventListener("keydown", this.keydown)
    this.element.removeEventListener("submit", this.submit)
    // Replaced (saved row) or removed : the guard recounts without it
    this.announce()
  }

  update() {
    const dirty = [...this.element.elements].some((el) => !el.hasAttribute("data-dirty-ignore") && changed(el))
    for (const button of this.submitTargets) button.disabled = !dirty
    if (dirty === this.element.hasAttribute("data-dirty")) return
    this.element.toggleAttribute("data-dirty", dirty)
    this.announce()
  }

  keydown(event) {
    if (event.key !== "Enter" || !(event.metaKey || event.ctrlKey) || event.target.tagName !== "TEXTAREA") return
    event.preventDefault()
    this.element.requestSubmit()
  }

  submit(event) {
    if (!this.hasSubmitTarget || this.element.hasAttribute("data-dirty")) return
    if (!event.submitter || this.submitTargets.includes(event.submitter)) event.preventDefault()
  }

  announce() {
    this.dispatch("change", { target: window })
  }
}

function changed(el) {
  if (el.type === "checkbox" || el.type === "radio") return el.checked !== el.defaultChecked
  if (el.tagName === "SELECT") {
    const options = [...el.options]
    if (el.multiple) return options.some((o) => o.selected !== o.defaultSelected)
    // Without a `selected` attribute the first option is the initial one
    return el.selectedIndex !== Math.max(0, options.findLastIndex((o) => o.defaultSelected))
  }
  if (el.tagName === "TEXTAREA" || el.tagName === "INPUT") return el.value !== el.defaultValue
  return false
}
