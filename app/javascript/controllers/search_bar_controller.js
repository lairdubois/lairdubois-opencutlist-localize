import { Controller } from "@hotwired/stimulus"

// Search bar (shared/_search_bar) : every change submits its GET form, which reloads the list.
// Field chips (key, branch, user, index) are rendered hidden and disabled until picked in the filters menu ;
// the user one holds a list of names (a popover) filling a hidden field, submitted as soon as a name is picked ;
// a status, the questions / warnings flag or the period is a hidden input inside its chip, so removing the chip drops it.
// A single index (no "-") is exclusive : applying it drops every other filter, any other change drops it.
// A range mixes with the rest.
// In the text search, keywords fill the field chips : #120 (or #120-180…), key:…, branch:…, user:… (a name,
// or the start of one : left in the text when no name matches)
// The sort (where offered) is not a filter : a menu of its own, its chip holding the sort and direction inputs,
// its arrow reversing it.
export default class extends Controller {
  static targets = ["chips", "field", "menu"]
  static FILTERS = ["q", "status[]", "questions", "warnings", "notranslate", "days", "key", "prefix", "user", "at"]
  static KEYWORDS = { at: /^#(\d+(?:-\d*)?|-\d+)$/, key: /^(?:key|cl[eé]):(.+)$/i, prefix: /^(?:branch|branche):(.+)$/i, user: /^(?:user|utilisateur):(.+)$/i }
  static REFOCUS = "search-bar:refocus"

  // A field submitted with Enter (or reset with Shift-Esc) gets the focus back on the rendered page,
  // the caret at the end (not on Turbo's cache preview). The text search if that chip went away.
  connect() {
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    let name
    try {
      name = sessionStorage.getItem(this.constructor.REFOCUS)
      sessionStorage.removeItem(this.constructor.REFOCUS)
    } catch {
      return
    }
    if (!name) return

    const inputs = [...this.element.querySelectorAll("input:not([type=hidden])")]
    const input = inputs.find((i) => i.name === name && !i.disabled) || inputs.find((i) => i.name === "q")
    input.focus()
    input.setSelectionRange(input.value.length, input.value.length)
  }

  refocus(name) {
    try {
      sessionStorage.setItem(this.constructor.REFOCUS, name)
    } catch {}
  }

  submit(event) {
    event?.preventDefault()
    if (event?.target instanceof HTMLInputElement) this.refocus(event.target.name)
    this.origin = event?.target?.name === "q" ? this.extract(event.target) : event?.target?.name
    this.element.requestSubmit()
  }

  // Moves the keywords of the text search to their field chip. Returns the change's origin : "at" when
  // an index was typed (a single one is exclusive), "q" otherwise
  extract(input) {
    let origin = "q"
    const words = input.value.trim().split(/\s+/)
    const rest = words.filter((word) => {
      const [name, match] = Object.entries(this.constructor.KEYWORDS).map(([n, re]) => [n, word.match(re)]).find(([, m]) => m) || []
      if (!match || !this.fill(name, match[1])) return true

      if (name === "at") origin = "at"
      return false
    })
    if (rest.length < words.length) input.value = rest.join(" ")
    return origin
  }

  // Returns false when a user keyword matches no name
  fill(name, value) {
    const chip = this.fieldTargets.find((c) => c.dataset.name === name)
    const input = chip.querySelector("input")
    if (name === "user") {
      value = this.userId(chip, value)
      if (!value) return false
    }
    input.value = value
    input.disabled = false
    chip.hidden = false
    this.chipsTarget.hidden = false
    return true
  }

  // The id of a typed name in the user chip's list, case and accents aside ("_" for a space) : the exact one,
  // else the only one whose first word it is, starting with it, or containing it
  userId(chip, value) {
    const normalize = (text) => text.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().trim()
    const typed = normalize(value.replaceAll("_", " "))
    const users = [...chip.querySelectorAll("[data-search-bar-user]")].map((b) => [normalize(b.textContent), b.dataset.searchBarIdParam])
    const exact = users.find(([name]) => name === typed)
    if (exact) return exact[1]

    for (const test of [(name) => name.split(/\s+/)[0] === typed, (name) => name.startsWith(typed), (name) => name.includes(typed)]) {
      const found = users.filter(([name]) => test(name))
      if (found.length === 1) return found[0][1]
    }
  }

  // Leaves empty fields out of the query string, and keeps a single index exclusive
  prune(event) {
    const at = event.formData.get("at") || ""
    const single = at !== "" && !at.includes("-")
    const index = single && this.origin === "at"
    for (const [name, value] of [...event.formData]) {
      const dropped = index ? name !== "at" && this.constructor.FILTERS.includes(name) : single && name === "at"
      if (value === "" || dropped) event.formData.delete(name)
    }
    this.origin = null
  }

  // Mod-F focuses the text search ; pressed again in it, the browser's own find takes over
  shortcut(event) {
    if (!(event.metaKey || event.ctrlKey) || event.altKey || event.shiftKey || event.key.toLowerCase() !== "f") return

    const input = this.element.querySelector("input[name=q]")
    if (document.activeElement === input) return

    event.preventDefault()
    input.focus()
    input.select()
  }

  // Esc gives the focus back to the page, the typed text kept (a search field would clear it) ;
  // a field chip left empty without having been applied then goes away (drop)
  blur(event) {
    event.preventDefault()
    event.target.blur()
  }

  clear(event) {
    event.currentTarget.parentElement.querySelector("input[name=q]").value = ""
    this.submit()
  }

  // Shows a field chip and focuses its input, or opens its list of names
  add({ params: { name } }) {
    const chip = this.fieldTargets.find((c) => c.dataset.name === name)
    const input = chip.querySelector("input")
    chip.hidden = false
    input.disabled = false
    this.chipsTarget.hidden = false
    this.menuTarget.hidePopover()
    if (name === "user") {
      chip.querySelector("[popover]").showPopover()
    } else {
      input.focus()
    }
  }

  pickUser({ params: { id } }) {
    const input = this.fieldTargets.find((c) => c.dataset.name === "user").querySelector("input")
    input.value = id
    input.disabled = false
    this.submit()
  }

  // Menus (the filters one, the user chip's list of names) : ↓ / ↑ on their button open them
  openMenu(event) {
    event.preventDefault()
    document.getElementById(event.currentTarget.getAttribute("popovertarget")).showPopover()
  }

  // A menu opened : the focus on its picked entry (a name), else the first one
  focusMenu(event) {
    if (event.newState !== "open") return

    const items = [...event.target.querySelectorAll("button")]
    ;(items.find((i) => i.getAttribute("role") === "menuitemradio" && i.getAttribute("aria-checked") === "true") || items[0])?.focus()
  }

  // In a menu : ↓ / ↑ move the focus (wrapping around), Home / End to the ends
  menuKeydown(event) {
    const items = [...event.currentTarget.querySelectorAll("button")]
    const index = items.indexOf(document.activeElement)
    const next = { ArrowDown: index + 1, ArrowUp: (index < 0 ? items.length : index) - 1, Home: 0, End: items.length - 1 }[event.key]
    if (next === undefined || !items.length) return

    event.preventDefault()
    items[(next + items.length) % items.length].focus()
  }

  // The list of names closed without a pick : an empty chip goes away, as a field left empty (drop)
  userToggled(event) {
    if (event.newState !== "closed") return

    const chip = event.target.closest("[data-chip]")
    const input = chip.querySelector("input")
    if (input.value !== "" || "applied" in chip.dataset) return

    chip.hidden = true
    input.disabled = true
    this.chipsTarget.hidden = !this.chipsTarget.querySelector("[data-chip]:not([hidden])")
  }

  // A field chip left empty without having been applied goes away, without reloading
  drop(event) {
    const chip = event.target.closest("[data-chip]")
    if (event.target.value !== "" || "applied" in chip.dataset) return

    chip.hidden = true
    event.target.disabled = true
    this.chipsTarget.hidden = !this.chipsTarget.querySelector("[data-chip]:not([hidden])")
  }

  remove(event) {
    event.currentTarget.closest("[data-chip]").remove()
    this.submit()
  }

  // Shift-Esc : the text search and every chip
  reset() {
    this.element.querySelector("input[name=q]").value = ""
    this.refocus("q")
    this.removeAll()
  }

  // Empties the chips area (filters and sort), the text search kept
  removeAll() {
    this.chipsTarget.querySelectorAll("[data-chip]").forEach((chip) => chip.remove())
    this.submit()
  }

  // Checks or unchecks a status / the questions or warnings flag
  toggle({ params: { name, value } }) {
    const input = [...this.element.querySelectorAll("input[type=hidden]")].find((i) => i.name === name && i.value === String(value))
    if (input) {
      input.closest("[data-chip]").remove()
    } else {
      const added = document.createElement("input")
      Object.assign(added, { type: "hidden", name, value })
      this.element.append(added)
    }
    this.submit()
  }

  // Picks the period (one at a time) : picked again, it is dropped
  choose({ params: { name, value } }) {
    const input = [...this.element.querySelectorAll("input[type=hidden]")].find((i) => i.name === name)
    if (input?.value === String(value)) {
      input.closest("[data-chip]").remove()
    } else {
      ;(input || this.element.appendChild(Object.assign(document.createElement("input"), { type: "hidden", name }))).value = value
    }
    this.submit()
  }

  // Picks a sort in its menu, in its own default direction
  sort(event) {
    const { sort, dir } = event.params
    event.currentTarget.closest("[popover]").hidePopover()
    const current = this.element.querySelector("input[type=hidden][name=sort]")
    if (current?.value === sort) return

    for (const [name, value] of [["sort", sort], ["dir", dir]]) {
      const input = this.element.querySelector(`input[type=hidden][name=${name}]`) || this.element.appendChild(Object.assign(document.createElement("input"), { type: "hidden", name }))
      input.value = value
    }
    this.submit()
  }

  // The sort chip's arrow
  reverse(event) {
    const input = event.currentTarget.closest("[data-chip]").querySelector("input[name=dir]")
    input.value = input.value === "desc" ? "asc" : "desc"
    this.submit()
  }
}
