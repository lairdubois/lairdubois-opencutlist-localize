import { EditorState, StateField } from "@codemirror/state"
import { EditorView, Decoration, WidgetType, keymap, highlightSpecialChars } from "@codemirror/view"
import { defaultKeymap, history, historyKeymap, insertNewline } from "@codemirror/commands"

// Invariants of an OCL string : a translation keeps them verbatim. Earlier kinds win on overlap,
// so a `code` span stays a single token whatever it holds, and a $t() wrapping a {{ variable }} or a tag
// carrying one in its href too.
const INVARIANTS = [
  ["code", /`[^`\n]+`/g],
  ["ref", /\$t\([^)\n]*\)/g],
  ["tag", /<\/?[a-zA-Z][^<>\n]*>/g],
  ["var", /\{\{-?\s*[^{}\n]+?\s*\}\}/g],
  ["entity", /&(?:[a-zA-Z]+|#\d+);/g],
]

// Same comparison as TranslationChecks : whitespace inside a token doesn't matter
const normalize = (token) => token.replace(/\s+/g, "")

// $t(key) or $t(key, { options })
const refKey = (token) => token.slice(3, -1).split(",")[0].trim()

function invariants(text) {
  const found = []
  for (const [kind, pattern] of INVARIANTS) {
    for (const m of text.matchAll(pattern)) {
      const from = m.index, to = from + m[0].length
      if (!found.some((t) => from < t.to && to > t.from)) found.push({ kind, from, to, text: m[0] })
    }
  }
  return found.sort((a, b) => a.from - b.from)
}

// Symbols hard to type (→, −, °, ×…) : non-ASCII Unicode symbols, and the dagger (punctuation). Not invariants :
// highlighted, and offered as chips when the translation has fewer than the source. Quotes (« ») aren't symbols.
const SYMBOL = /(?![\x00-\x7f])[\p{S}†‡]/gu

function symbols(text, skip = invariants(text)) {
  return [...text.matchAll(SYMBOL)]
    .map((m) => ({ from: m.index, to: m.index + m[0].length, text: m[0] }))
    .filter((t) => !skip.some((s) => t.from < s.to && t.to > s.from))
}

// Markdown markers, highlighted only : translators may move them
function markup(text, skip) {
  const out = []
  const free = (from, to) => !skip.some((t) => from < t.to && to > t.from)
  const add = (cls, from, to) => { if (from < to && free(from, to)) out.push({ cls, from, to }) }
  for (const m of text.matchAll(/\*\*(?=\S)([^\n]*?\S)\*\*/g)) {
    const end = m.index + m[0].length
    add("tok-mark", m.index, m.index + 2)
    add("tok-mark", end - 2, end)
    out.push({ cls: "tok-strong", from: m.index + 2, to: end - 2 })
  }
  for (const m of text.matchAll(/(?<![*\w])\*(?=[^\s*])([^*\n]*?[^\s*])?\*(?![*\w])/g)) {
    const end = m.index + m[0].length
    add("tok-mark", m.index, m.index + 1)
    add("tok-mark", end - 1, end)
    out.push({ cls: "tok-em", from: m.index + 1, to: end - 1 })
  }
  // [text](url) : brackets and parentheses as markers, the url may hold one level of parentheses
  // (wikipedia.org/wiki/STL_(file_format))
  for (const m of text.matchAll(/\[([^\]\n]+)\]\(((?:[^()\s]|\([^()\s]*\))+)\)/g)) {
    const close = m.index + 1 + m[1].length, end = m.index + m[0].length
    add("tok-mark", m.index, m.index + 1)
    out.push({ cls: "tok-link", from: m.index + 1, to: close })
    add("tok-mark", close, close + 2)
    add("tok-url", close + 2, end - 1)
    add("tok-mark", end - 1, end)
  }
  for (const m of text.matchAll(/^[ \t]*([-*]) /gm)) {
    const at = m.index + m[0].length - 2
    add("tok-mark", at, at + 1)
  }
  return out
}

// Shown only when the "show whitespace" toggle is on (html.show-ws), see application.css
class EndOfLine extends WidgetType {
  eq() { return true }
  toDOM() {
    const span = document.createElement("span")
    span.className = "ws-eol"
    span.textContent = "↵"
    return span
  }
}
const endOfLine = Decoration.widget({ widget: new EndOfLine(), side: 1 })

// Case and accents aside, as the server's search (SqliteFold)
const fold = (text) => text.normalize("NFD").replace(/\p{Mn}/gu, "").toLowerCase()

// The folded text (unless exact), and the offset in text of each folded character's source
function foldMap(text, exact) {
  let folded = ""
  const origins = []
  for (let i = 0; i < text.length;) {
    const char = String.fromCodePoint(text.codePointAt(i))
    const f = exact ? char : fold(char)
    folded += f
    for (let k = 0; k < f.length; k++) origins.push(i)
    i += char.length
  }
  origins.push(text.length)
  // The range of text whose folding is folded[at, at + length)
  const range = (at, length) => {
    const last = origins[at + length - 1]
    return { from: origins[at], to: last + String.fromCodePoint(text.codePointAt(last)).length }
  }
  return { folded, range }
}

// The ranges of text matching search : exact, or folded
function searchHits(text, search, exact) {
  const pattern = exact ? search : fold(search)
  if (!pattern) return []

  const { folded, range } = foldMap(text, exact)
  const hits = []
  for (let at = folded.indexOf(pattern); at >= 0; at = folded.indexOf(pattern, at + pattern.length)) hits.push(range(at, pattern.length))
  return hits
}

// Same matching as the server's Glossary : whole words (not at an edge written in a script without spaces), case and
// accents aside, any whitespace inside a form, invariants left out ; the longest wins on overlap
const UNSPACED = /[\p{sc=Han}\p{sc=Hiragana}\p{sc=Katakana}\p{sc=Thai}\p{sc=Lao}\p{sc=Khmer}\p{sc=Myanmar}]/u
const WORD_CHAR = /[\p{L}\p{N}_]/u
const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

// glossary : [{ forms, title }], the terms the server found in the text
function glossaryHits(text, glossary, skip) {
  if (!glossary.length) return []

  const { folded, range } = foldMap(text, false)
  const hits = []
  for (const { forms, title } of glossary) {
    for (const form of forms) {
      const words = fold(form).trim().split(/\s+/).filter(Boolean)
      if (!words.length) continue
      const pattern = new RegExp(words.map(escapeRegExp).join("\\s+"), "gu")
      for (const m of folded.matchAll(pattern)) {
        const end = m.index + m[0].length
        if (!UNSPACED.test(m[0].at(0)) && WORD_CHAR.test(folded[m.index - 1] || "")) continue
        if (!UNSPACED.test(m[0].at(-1)) && WORD_CHAR.test(folded[end] || "")) continue
        hits.push({ ...range(m.index, m[0].length), title })
      }
    }
  }
  const kept = []
  for (const h of hits.sort((a, b) => (b.to - b.from) - (a.to - a.from) || a.from - b.from)) {
    const free = (t) => !(h.from < t.to && h.to > t.from)
    if (kept.every(free) && skip.every(free)) kept.push(h)
  }
  return kept
}

// Decorations of a text, and the ranges locked in the editor (invariants also in the source)
function analyse(text, { source, refs, glossary, editable, search, searchExact }) {
  const expected = source == null ? null : new Set(invariants(source).map((t) => normalize(t.text)))
  const tokens = invariants(text)
  const marks = []
  const locked = []
  const links = []
  for (const t of tokens) {
    const known = !expected || expected.has(normalize(t.text))
    const ref = t.kind === "ref" ? refs[refKey(t.text)] : null
    const attributes = ref ? { title: ref.title, ...(ref.url && { "data-ref-url": "" }) } : undefined
    marks.push(Decoration.mark({ class: `tok-${t.kind}${known ? "" : " tok-unknown"}`, attributes }).range(t.from, t.to))
    if (ref?.url) links.push({ from: t.from, to: t.to, url: ref.url })
    if (editable && expected && known) locked.push(t)
  }
  for (const t of symbols(text, tokens)) marks.push(Decoration.mark({ class: "tok-symbol" }).range(t.from, t.to))
  for (const h of glossaryHits(text, glossary, tokens)) marks.push(Decoration.mark({ class: "tok-glossary", attributes: { title: h.title } }).range(h.from, h.to))
  for (const m of markup(text, tokens)) marks.push(Decoration.mark({ class: m.cls }).range(m.from, m.to))
  for (const m of text.matchAll(/[ \u00a0\t]/g)) {
    const cls = m[0] === " " ? "ws-space" : m[0] === "\t" ? "ws-tab" : "ws-nbsp"
    marks.push(Decoration.mark({ class: cls }).range(m.index, m.index + 1))
  }
  for (const m of text.matchAll(/[ \u00a0\t]+$/gm)) marks.push(Decoration.mark({ class: "ws-trailing" }).range(m.index, m.index + m[0].length))
  for (const m of text.matchAll(/\n/g)) marks.push(endOfLine.range(m.index))
  if (search) for (const h of searchHits(text, search, searchExact)) marks.push(Decoration.mark({ class: "search-hit" }).range(h.from, h.to))
  return {
    decorations: Decoration.set(marks, true),
    atomic: Decoration.set(locked.map((t) => Decoration.mark({}).range(t.from, t.to))),
    locked,
    links,
  }
}

// Source tokens the translation has fewer of than the source, first spelling of each
function missing(sourceTokens, textTokens, key) {
  const count = new Map()
  for (const t of textTokens) count.set(key(t.text), (count.get(key(t.text)) || 0) + 1)
  const spelling = new Map()
  const lacking = new Set()
  for (const t of sourceTokens) {
    const k = key(t.text)
    if (!spelling.has(k)) spelling.set(k, t.text)
    if (count.get(k) > 0) count.set(k, count.get(k) - 1)
    else lacking.add(k)
  }
  return [...lacking].map((k) => spelling.get(k))
}

export const missingInvariants = (source, text) => missing(invariants(source), invariants(text), normalize)

export const missingSymbols = (source, text) => missing(symbols(source), symbols(text), (t) => t)

// Edits starting or ending strictly inside a locked token are refused ; removing it whole is fine
const protectInvariants = (field) => EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged) return tr
  const { locked } = tr.startState.field(field)
  let ok = true
  tr.changes.iterChangedRanges((fromA, toA) => {
    if (locked.some((t) => (fromA > t.from && fromA < t.to) || (toA > t.from && toA < t.to))) ok = false
  })
  return ok ? tr : []
})

// Mod-click (Cmd, or Ctrl) on a $t() opens its key in a new tab, instead of adding a cursor. While the key is down,
// data-mod-key on the editor shows the links (application.css).
const modKey = (event) => event.metaKey || event.ctrlKey
const openRefs = (field) => EditorView.domEventHandlers({
  mousedown(event, view) {
    if (!modKey(event) || event.button !== 0) return false
    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY }, false)
    const link = view.state.field(field).links.find((l) => pos >= l.from && pos < l.to)
    if (!link) return false
    event.preventDefault()
    window.open(link.url, "_blank", "noopener")
    return true
  },
  mousemove(event, view) { view.dom.toggleAttribute("data-mod-key", modKey(event)) },
  mouseleave(event, view) { view.dom.removeAttribute("data-mod-key") },
  keydown(event, view) { view.dom.toggleAttribute("data-mod-key", modKey(event)) },
  keyup(event, view) { view.dom.toggleAttribute("data-mod-key", modKey(event)) },
})

// Font size and family come from the host (text-sm font-mono) : a size set here would beat Tailwind's
const layout = EditorView.theme({
  "&.cm-focused": { outline: "2px solid var(--color-stone-400)", outlineOffset: "-1px" },
  ".cm-scroller": { fontFamily: "inherit", lineHeight: "inherit" },
  ".cm-content": { padding: "0" },
  ".cm-line": { padding: "0" },
})

// A CodeMirror view of an OCL string : the translator's editor, or a read-only reference.
// source : the fr text ; invariants it lacks are flagged, the ones it has are locked in an editor (null :
// nothing flagged nor locked, e.g. the fr source itself) ; refs : $t() key => { title (tooltip), url (opened by Mod-click) } ;
// glossary : [{ forms, title }], its terms underlined, their tooltip in the title.
// className : extra classes of the editor element (CodeMirror rewrites its class attribute, classList.add doesn't last).
// search : the list's searched text, its matches highlighted (searchExact : case and accents included).
export function createI18nView({ parent, text, source = null, refs = {}, glossary = [], editable = false, lang, dir = "ltr", className = "", search = "", searchExact = false, onChange, onSubmit }) {
  const options = { source, refs, glossary, editable, search, searchExact }
  const field = StateField.define({
    create: (state) => analyse(state.doc.toString(), options),
    update: (value, tr) => (tr.docChanged ? analyse(tr.state.doc.toString(), options) : value),
    provide: (f) => [EditorView.decorations.from(f, (v) => v.decorations), EditorView.atomicRanges.of((view) => view.state.field(f).atomic)],
  })
  const extensions = [
    field,
    openRefs(field),
    layout,
    EditorView.lineWrapping,
    highlightSpecialChars(),
    EditorView.editorAttributes.of({ dir, class: `${editable ? "i18n-editor" : "i18n-readonly"} ${className}`.trim() }),
  ]
  if (editable) {
    extensions.push(
      protectInvariants(field),
      history(),
      // Plain newline : no indentation copied from the previous line
      // Mod-Enter saves, Shift-Mod-Enter saves and approves
      // Tab / Shift-Tab : the page's next / previous editor, skipping the buttons between them
      keymap.of([{ key: "Mod-Enter", run: () => { onSubmit?.(); return true }, shift: () => { onSubmit?.({ review: true }); return true } }, { key: "Enter", run: insertNewline },
        { key: "Tab", run: (view) => focusSibling(view, 1), shift: (view) => focusSibling(view, -1) }, ...defaultKeymap, ...historyKeymap]),
      EditorView.contentAttributes.of({ spellcheck: "true", lang: lang || "", autocorrect: "off", autocapitalize: "off" }),
      EditorView.updateListener.of((update) => { if (update.docChanged) onChange?.(update.state.doc.toString()) }),
    )
  } else {
    extensions.push(EditorState.readOnly.of(true), EditorView.editable.of(false))
  }
  return new EditorView({ parent, state: EditorState.create({ doc: text, extensions }) })
}

// Replaces the whole text from outside (suggestion buttons), bypassing the invariant lock
export function replaceText(view, text) {
  if (view.state.doc.toString() === text) return
  view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, filter: false })
}

// Inserts a token at the cursor (invariant chips)
export function insertText(view, text) {
  const { from, to } = view.state.selection.main
  view.dispatch({ changes: { from, to, insert: text }, selection: { anchor: from + text.length }, scrollIntoView: true, userEvent: "input" })
  view.focus()
}

// Moves the focus to the next (1) or previous (-1) visible editor of the page, cursor at the end. None
// (the first or last one) : false, the browser's Tab goes on (e.g. to the buttons after the last one)
export function focusSibling(view, step) {
  const editors = [...document.querySelectorAll(".cm-editor.i18n-editor")].filter((el) => el.getClientRects().length)
  const target = editors[editors.indexOf(view.dom) + step]
  const sibling = target && EditorView.findFromDOM(target)
  if (!sibling) return false
  focusEnd(sibling)
  return true
}

// Focuses the editor, cursor at the end of the text
export function focusEnd(view) {
  view.dispatch({ selection: { anchor: view.state.doc.length }, scrollIntoView: true })
  view.focus()
}
