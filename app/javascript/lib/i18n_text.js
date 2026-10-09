import { EditorState, StateField } from "@codemirror/state"
import { EditorView, Decoration, WidgetType, keymap, highlightSpecialChars } from "@codemirror/view"
import { defaultKeymap, history, historyKeymap, insertNewline } from "@codemirror/commands"

// Invariants of an OCL string : a translation keeps them verbatim. Earlier kinds win on overlap,
// so a $t() wrapping a {{ variable }} or a tag carrying one in its href stays a single token.
const INVARIANTS = [
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

// Decorations of a text, and the ranges locked in the editor (invariants also in the source)
function analyse(text, { source, refs, editable }) {
  const expected = source == null ? null : new Set(invariants(source).map((t) => normalize(t.text)))
  const tokens = invariants(text)
  const marks = []
  const locked = []
  for (const t of tokens) {
    const known = !expected || expected.has(normalize(t.text))
    const attributes = t.kind === "ref" && refs[refKey(t.text)] ? { title: refs[refKey(t.text)] } : undefined
    marks.push(Decoration.mark({ class: `tok-${t.kind}${known ? "" : " tok-unknown"}`, attributes }).range(t.from, t.to))
    if (editable && expected && known) locked.push(t)
  }
  for (const m of markup(text, tokens)) marks.push(Decoration.mark({ class: m.cls }).range(m.from, m.to))
  for (const m of text.matchAll(/[ \u00a0\t]/g)) {
    const cls = m[0] === " " ? "ws-space" : m[0] === "\t" ? "ws-tab" : "ws-nbsp"
    marks.push(Decoration.mark({ class: cls }).range(m.index, m.index + 1))
  }
  for (const m of text.matchAll(/[ \u00a0\t]+$/gm)) marks.push(Decoration.mark({ class: "ws-trailing" }).range(m.index, m.index + m[0].length))
  for (const m of text.matchAll(/\n/g)) marks.push(endOfLine.range(m.index))
  return {
    decorations: Decoration.set(marks, true),
    atomic: Decoration.set(locked.map((t) => Decoration.mark({}).range(t.from, t.to))),
    locked,
  }
}

// Source invariants the translation has fewer of than the source, first spelling of each
export function missingInvariants(source, text) {
  const count = new Map()
  for (const t of invariants(text)) count.set(normalize(t.text), (count.get(normalize(t.text)) || 0) + 1)
  const spelling = new Map()
  const missing = new Set()
  for (const t of invariants(source)) {
    const key = normalize(t.text)
    if (!spelling.has(key)) spelling.set(key, t.text)
    if (count.get(key) > 0) count.set(key, count.get(key) - 1)
    else missing.add(key)
  }
  return [...missing].map((key) => spelling.get(key))
}

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

// Font size and family come from the host (text-sm font-mono) : a size set here would beat Tailwind's
const layout = EditorView.theme({
  "&.cm-focused": { outline: "2px solid var(--color-stone-400)", outlineOffset: "-1px" },
  ".cm-scroller": { fontFamily: "inherit", lineHeight: "inherit" },
  ".cm-content": { padding: "0" },
  ".cm-line": { padding: "0" },
})

// A CodeMirror view of an OCL string : the translator's editor, or a read-only reference.
// source : the fr text ; invariants it lacks are flagged, the ones it has are locked in an editor (null :
// nothing flagged nor locked, e.g. the fr source itself) ; refs : $t() key => fr text (tooltips).
// className : extra classes of the editor element (CodeMirror rewrites its class attribute, classList.add doesn't last).
export function createI18nView({ parent, text, source = null, refs = {}, editable = false, lang, dir = "ltr", className = "", onChange, onSubmit }) {
  const options = { source, refs, editable }
  const field = StateField.define({
    create: (state) => analyse(state.doc.toString(), options),
    update: (value, tr) => (tr.docChanged ? analyse(tr.state.doc.toString(), options) : value),
    provide: (f) => [EditorView.decorations.from(f, (v) => v.decorations), EditorView.atomicRanges.of((view) => view.state.field(f).atomic)],
  })
  const extensions = [
    field,
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
      keymap.of([{ key: "Mod-Enter", run: () => { onSubmit?.(); return true }, shift: () => { onSubmit?.({ review: true }); return true } }, { key: "Enter", run: insertNewline }, ...defaultKeymap, ...historyKeymap]),
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
