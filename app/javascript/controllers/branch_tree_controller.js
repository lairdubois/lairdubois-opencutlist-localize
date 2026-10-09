import { Controller } from "@hotwired/stimulus"

// In the paged list a branch spanning several pages is repeated ("continued") on the next ones.
// The first occurrence rules : while it is closed, the continuations are hidden (closing it may
// bring the next page into view, whose continuation must not show the branch again).
export default class extends Controller {
  static targets = ["branch"]

  // toggle doesn't bubble : bound with :capture
  sync(event) {
    const details = event.target
    if (!this.branchTargets.includes(details)) return

    const [first, ...continuations] = this.occurrences(details.dataset.path)
    if (details !== first) {
      // A continuation closed by hand closes the branch from its start
      if (!details.open && !details.hidden) {
        first.open = false
        first.scrollIntoView({ block: "nearest" })
      }
      return
    }
    continuations.forEach(continuation => {
      continuation.hidden = !first.open
      continuation.open = true
    })
  }

  branchTargetConnected(details) {
    const [first] = this.occurrences(details.dataset.path)
    if (first !== details) details.hidden = !first.open
  }

  occurrences(path) {
    return this.branchTargets.filter(details => details.dataset.path === path)
  }
}
