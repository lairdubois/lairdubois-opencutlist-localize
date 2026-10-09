import { Controller } from "@hotwired/stimulus"
import { createI18nView, replaceText, insertText, missingInvariants } from "lib/i18n_text"

// Shows an OCL string in CodeMirror : invariants highlighted, whitespace revealed on demand.
// On a form with a `field` textarea : an editor, the textarea kept hidden and in sync. With a `source`
// value (translator's editor), the source's {{ variables }}, $t() and tags are locked and the missing ones
// offered as chips ; without (fr source editor), nothing is locked. Mod-Enter submits, Shift-Mod-Enter
// through the `review` button, hidden while the text is blank (a blank save removes the translation).
// On any other element : a read-only view of the `text` value, invariants missing from `source` (if
// given) flagged.
export default class extends Controller {
  static targets = ["field", "chips", "review"]
  static values = { text: String, source: String, refs: Object }

  connect() {
    // A Turbo cache snapshot keeps the previous view's DOM : start clean
    this.element.querySelectorAll(".cm-editor").forEach((el) => el.remove())
    this.hasFieldTarget ? this.connectEditor() : this.connectReadOnly()
  }

  disconnect() {
    this.view?.destroy()
    if (this.hasFieldTarget) {
      this.fieldTarget.hidden = false
      this.fieldTarget.removeEventListener("input", this.pull)
    } else {
      this.element.textContent = this.textValue
    }
  }

  connectReadOnly() {
    this.element.textContent = ""
    this.view = createI18nView({
      parent: this.element,
      text: this.textValue,
      source: this.hasSourceValue ? this.sourceValue : null,
      refs: this.refsValue,
      dir: this.element.dir || "ltr",
    })
  }

  connectEditor() {
    const field = this.fieldTarget
    this.view = createI18nView({
      parent: this.element,
      text: field.value,
      source: this.hasSourceValue ? this.sourceValue : null,
      refs: this.refsValue,
      editable: true,
      lang: field.lang,
      dir: field.dir,
      // Takes the textarea's place (and classes) in the row's grid
      className: field.className,
      // Announced for dirty-form : setting the value doesn't fire `input`
      onChange: (text) => { field.value = text; this.renderChips(); this.toggleReview(); this.dispatch("change") },
      // Without a review button (not a reviewer, or a blank text), Shift-Mod-Enter is a plain save
      onSubmit: ({ review } = {}) => this.element.requestSubmit(review && this.hasReviewTarget && !this.reviewTarget.hidden ? this.reviewTarget : undefined),
    })
    field.after(this.view.dom)
    field.hidden = true
    // Suggestion buttons fill the textarea and fire `input`
    this.pull = () => replaceText(this.view, field.value)
    field.addEventListener("input", this.pull)
    this.renderChips()
    this.toggleReview()
  }

  toggleReview() {
    if (this.hasReviewTarget) this.reviewTarget.hidden = this.fieldTarget.value.trim() === ""
  }

  renderChips() {
    if (!this.hasChipsTarget || !this.hasSourceValue) return
    const missing = missingInvariants(this.sourceValue, this.view.state.doc.toString())
    this.chipsTarget.replaceChildren(...missing.map((token) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "tok-chip"
      button.textContent = token
      button.addEventListener("click", () => insertText(this.view, token))
      return button
    }))
    this.chipsTarget.hidden = missing.length === 0
  }
}
