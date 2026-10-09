import { Controller } from "@hotwired/stimulus"

// Places a native popover right under its anchor, right edges aligned (left ones with
// data-popover-align-value="left") ; popovers live in the top layer, centered in the viewport by default
export default class extends Controller {
  static targets = ["anchor", "panel"]
  static values = { align: { type: String, default: "right" } }

  place(event) {
    if (event.newState !== "open") return

    const rect = this.anchorTarget.getBoundingClientRect()
    Object.assign(this.panelTarget.style, {
      position: "fixed",
      inset: "auto",
      top: `${rect.bottom + 4}px`,
      ...(this.alignValue === "left" ? { left: `${rect.left}px` } : { right: `${document.documentElement.clientWidth - rect.right}px` }),
    })
  }
}
