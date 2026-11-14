import { Controller } from "@hotwired/stimulus"

const DURATION = 2500 // ms the hint stays
const GAP = 6 // px between the box and the hint
const MARGIN = 8 // px kept from the viewport edges

// A reader's text box (translator's list) : a click in it, where a translator would edit, shows a short
// hint that the language is read only. One hint for the page, a manual popover (top layer, never
// clipped, menus left open) under the box, at the click's x. Not when the click selects text nor
// follows a $t() link (Mod-click).
export default class extends Controller {
  static values = { message: String }

  show(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.target.closest("a, button")) return
    if (!getSelection().isCollapsed) return

    const hint = this.hint
    hint.textContent = this.messageValue
    hint.style.position = "fixed"
    hint.style.inset = "auto"
    if (!hint.matches(":popover-open")) hint.showPopover()

    const rect = this.element.getBoundingClientRect()
    const viewport = document.documentElement
    const width = hint.offsetWidth
    const height = hint.offsetHeight
    const left = Math.min(Math.max(event.clientX - width / 2, MARGIN), viewport.clientWidth - width - MARGIN)
    const below = rect.bottom + GAP + height <= viewport.clientHeight - MARGIN
    hint.style.left = `${Math.max(left, MARGIN)}px`
    hint.style.top = `${below ? rect.bottom + GAP : Math.max(rect.top - GAP - height, MARGIN)}px`

    clearTimeout(hint.timer)
    hint.timer = setTimeout(() => hint.hidePopover(), DURATION)
  }

  disconnect() {
    const hint = document.getElementById("read-only-hint")
    if (hint?.matches(":popover-open")) hint.hidePopover()
  }

  get hint() {
    let hint = document.getElementById("read-only-hint")
    if (!hint) {
      hint = document.createElement("div")
      hint.id = "read-only-hint"
      hint.popover = "manual"
      hint.setAttribute("role", "status")
      hint.className = "pointer-events-none m-0 max-w-80 rounded border border-stone-300 bg-white px-2.5 py-1.5 text-xs text-stone-700 shadow-md"
      document.body.append(hint)
      addEventListener("scroll", () => hint.matches(":popover-open") && hint.hidePopover(), { capture: true, passive: true })
    }
    return hint
  }
}
