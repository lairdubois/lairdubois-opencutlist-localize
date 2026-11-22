import { Controller } from "@hotwired/stimulus"

// A field saved by Enter (the form's own submission) : Esc or leaving it gives the stored value back
export default class extends Controller {
  cancel(event) {
    const field = event.target
    field.value = field.defaultValue
    if (event.type === "keydown") field.blur()
  }
}
