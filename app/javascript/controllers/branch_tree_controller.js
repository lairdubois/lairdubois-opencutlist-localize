import { Controller } from "@hotwired/stimulus"

// In the paged list a branch spanning several pages is repeated ("continued") on the next ones.
// When a next page comes in, a continuation's children are moved to the end of the branch's first
// occurrence and the continuation is removed : the tree reads as one, with no repeated branch names.
// A continuation with no earlier occurrence (a page opened directly) stays, labelled as such.
export default class extends Controller {
  static targets = ["branch"]

  branchTargetConnected(details) {
    if (!details.hasAttribute("data-continued")) return

    const first = this.branchTargets.find(other => other.dataset.path === details.dataset.path)
    if (!first || first === details) return

    const into = first.querySelector(":scope > [data-children]")
    const from = details.querySelector(":scope > [data-children]")
    into.append(...from.childNodes)
    details.remove()
  }
}
