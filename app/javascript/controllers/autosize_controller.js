import { Controller } from "@hotwired/stimulus"

// Grows a textarea with its content. Sets min-height only, so the textarea can still
// stretch to a taller neighbour in its grid row.
export default class extends Controller {
  connect() {
    this.resize = this.resize.bind(this)
    window.addEventListener("resize", this.resize)
    this.resize()
  }

  disconnect() {
    window.removeEventListener("resize", this.resize)
  }

  resize() {
    const el = this.element
    const { height } = el.style
    el.style.height = "0"
    el.style.minHeight = "0"
    const border = el.offsetHeight - el.clientHeight
    const needed = el.scrollHeight + border
    el.style.height = height
    el.style.minHeight = `${needed}px`
  }
}
