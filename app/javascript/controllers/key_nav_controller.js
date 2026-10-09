import { Controller } from "@hotwired/stimulus"

// ← / → follow a key page's previous / next links when the focus isn't in a text field (there the
// arrows move the caret), Ctrl-Alt-← / → from anywhere. A click, so Turbo and the unsaved edits guard apply.
export default class extends Controller {
  static targets = ["previous", "next"]

  navigate(event) {
    if (event.metaKey || event.shiftKey || event.defaultPrevented) return
    if (event.ctrlKey !== event.altKey) return
    if (!event.ctrlKey && event.target.closest("input, textarea, select, [contenteditable]:not([contenteditable=false])")) return

    const link = { ArrowLeft: this.previousTargets[0], ArrowRight: this.nextTargets[0] }[event.key]
    if (!link) return

    event.preventDefault()
    link.click()
  }
}
