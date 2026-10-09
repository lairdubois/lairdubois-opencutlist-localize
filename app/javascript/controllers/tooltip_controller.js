import { Controller } from "@hotwired/stimulus"

const DELAY = 150 // ms before showing
const WARM = 400 // ms after hiding during which the next one shows at once
const GAP = 6 // px between the anchor and the tooltip
const MARGIN = 8 // px kept from the viewport edges

// Quick tooltips for every `title` of the page, in place of the browser's slow ones. On hover (or on
// keyboard focus) the title is moved to `data-tooltip-title`, so the native one doesn't show too, and
// put back on leave. Shown as a manual popover : in the top layer, never clipped by an overflow, and
// without closing the open menus. Under its anchor, centered, above it near the bottom of the viewport.
export default class extends Controller {
  connect() {
    this.tip = document.createElement("div")
    this.tip.id = "tooltip"
    this.tip.popover = "manual"
    this.tip.setAttribute("role", "tooltip")
    this.tip.className = "pointer-events-none m-0 max-w-96 rounded border-0 bg-stone-800 px-2 py-1 text-xs whitespace-pre-line text-white shadow-md"
    this.element.append(this.tip)

    this.over = this.over.bind(this)
    this.out = this.out.bind(this)
    this.focus = this.focus.bind(this)
    this.hide = this.hide.bind(this)
    this.close = this.close.bind(this)
    this.key = this.key.bind(this)
    document.addEventListener("pointerover", this.over)
    document.addEventListener("pointerout", this.out)
    document.addEventListener("focusin", this.focus)
    document.addEventListener("focusout", this.out)
    document.addEventListener("pointerdown", this.close, true)
    document.addEventListener("keydown", this.key, true)
    addEventListener("scroll", this.close, true)
    // The anchor may go away with a frame or a stream, the page into Turbo's cache : title put back first
    for (const name of ["turbo:before-cache", "turbo:before-frame-render", "turbo:before-stream-render", "turbo:visit"]) {
      addEventListener(name, this.hide)
    }
  }

  disconnect() {
    this.hide()
    this.tip.remove()
    document.removeEventListener("pointerover", this.over)
    document.removeEventListener("pointerout", this.out)
    document.removeEventListener("focusin", this.focus)
    document.removeEventListener("focusout", this.out)
    document.removeEventListener("pointerdown", this.close, true)
    document.removeEventListener("keydown", this.key, true)
    removeEventListener("scroll", this.close, true)
    for (const name of ["turbo:before-cache", "turbo:before-frame-render", "turbo:before-stream-render", "turbo:visit"]) {
      removeEventListener(name, this.hide)
    }
  }

  // Not on a touch screen (no native tooltip there either) : pointer events tell the touch from the
  // mouse, the mouse events emulated after a tap don't
  over(event) {
    if (event.pointerType === "touch") return

    const anchor = this.anchorOf(event.target)
    if (anchor && anchor !== this.anchor) this.schedule(anchor)
  }

  // Keyboard focus only : a click focuses its button too
  focus(event) {
    const anchor = this.anchorOf(event.target)
    if (anchor && anchor !== this.anchor && anchor.matches(":focus-visible")) this.schedule(anchor)
  }

  out(event) {
    if (!this.anchor || !this.anchor.contains(event.target)) return
    if (event.relatedTarget && this.anchor.contains(event.relatedTarget)) return

    this.hide()
  }

  key(event) {
    if (event.key === "Escape") this.close()
  }

  // Innermost element with a non-empty title (not an SVG's <title> child, which is an element)
  anchorOf(target) {
    const anchor = target instanceof Element ? target.closest("[title], [data-tooltip-title]") : null
    if (!anchor || anchor === this.tip) return null
    return anchor === this.anchor || anchor.getAttribute("title")?.trim() ? anchor : null
  }

  schedule(anchor) {
    const warm = this.tip.matches(":popover-open") || performance.now() - (this.hiddenAt ?? -Infinity) < WARM
    this.hide()
    this.anchor = anchor
    anchor.dataset.tooltipTitle = anchor.getAttribute("title")
    anchor.removeAttribute("title")
    anchor.setAttribute("aria-describedby", this.tip.id)
    if (warm) this.show()
    else this.timer = setTimeout(() => this.show(), DELAY)
  }

  show() {
    const anchor = this.anchor
    if (!anchor?.isConnected) return this.hide()

    this.tip.textContent = anchor.dataset.tooltipTitle
    this.tip.style.position = "fixed"
    this.tip.style.inset = "auto"
    this.tip.showPopover()

    const rect = anchor.getBoundingClientRect()
    const width = this.tip.offsetWidth
    const height = this.tip.offsetHeight
    const viewport = document.documentElement
    const left = Math.min(Math.max(rect.left + rect.width / 2 - width / 2, MARGIN), viewport.clientWidth - width - MARGIN)
    const below = rect.bottom + GAP + height <= viewport.clientHeight - MARGIN
    this.tip.style.left = `${Math.max(left, MARGIN)}px`
    this.tip.style.top = `${below ? rect.bottom + GAP : Math.max(rect.top - GAP - height, MARGIN)}px`
  }

  // Hides the tooltip, the anchor keeping its title away until left (as after a click on a native one)
  close() {
    clearTimeout(this.timer)
    if (!this.tip.matches(":popover-open")) return

    this.tip.hidePopover()
    this.hiddenAt = performance.now()
  }

  // Hides the tooltip and gives its anchor its title back
  hide() {
    this.close()
    const anchor = this.anchor
    if (!anchor) return

    this.anchor = null
    // Not over a title changed meanwhile
    if (!anchor.hasAttribute("title")) anchor.setAttribute("title", anchor.dataset.tooltipTitle)
    delete anchor.dataset.tooltipTitle
    if (anchor.getAttribute("aria-describedby") === this.tip.id) anchor.removeAttribute("aria-describedby")
  }
}
