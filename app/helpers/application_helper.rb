module ApplicationHelper
  # Status dot classes, shared by the search bar filters and the translator's editor badges
  STATUS_DOTS = {
    "untranslated" => "bg-yellow-400",
    "outdated" => "bg-orange-500",
    "unreviewed" => "bg-sky-500",
    "reviewed" => "bg-emerald-500"
  }.freeze

  # Header sections, by the controllers their pages belong to
  NAV_SECTIONS = {
    keys: %w[units comments branches],
    translate: %w[languages translations reference_languages],
    sync: %w[syncs],
    users: %w[users],
    migration: %w[migrations],
    publish: %w[publications github_accounts]
  }.freeze

  # Header link, underlined (tab-like, on the header's bottom edge) when the current page is in its section
  def nav_link(section, path)
    active = NAV_SECTIONS[section].include?(controller_name)
    link_to t("layouts.application.#{section}"), path, aria: { current: ("page" if active) },
            class: ["flex h-full items-center border-b-2 pt-0.5",
                    active ? "border-stone-800 font-medium text-stone-900" : "border-transparent text-stone-600 hover:text-stone-900"]
  end

  def status_dot(status, extra = nil)
    tag.span(class: ["h-2 w-2 shrink-0 rounded-full", STATUS_DOTS[status], extra])
  end

  # A collapsible section's state, as the user left it (collapsible controller's cookie)
  def section_open?(name, default:)
    state = cookies["section_#{name}"]
    state ? state == "open" : default
  end

  # Disclosure caret (heroicons chevron-right), in its button's color ; `extra` gives its rotation when open, spelled out for Tailwind
  def chevron_icon(extra = nil)
    tag.svg(tag.path("stroke-linecap": "round", "stroke-linejoin": "round", d: "m8.25 4.5 7.5 7.5-7.5 7.5"),
            viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 2.5, aria: { hidden: true },
            class: ["h-3 w-3 shrink-0 transition-transform", extra])
  end

  # Marks of the whitespace inside a change, which would be invisible otherwise
  DIFF_WHITESPACE = { " " => "·", "\u00A0" => "⍽", "\t" => "→", "\n" => "↵\n" }.freeze

  # WordDiff chunks : deletions struck in red, insertions in green, their whitespace marked
  def word_diff_tag(chunks)
    safe_join(chunks.map do |op, text|
      case op
      when :del then tag.del(diff_whitespace(text), class: "rounded-sm bg-red-100 text-red-800")
      when :ins then tag.ins(diff_whitespace(text), class: "rounded-sm bg-emerald-100 text-emerald-900 no-underline")
      else text
      end
    end)
  end

  def diff_whitespace(text)
    safe_join(text.split(/([ \u00A0\t\n])/).map do |part|
      (mark = DIFF_WHITESPACE[part]) ? tag.span(mark, class: "opacity-50") : part
    end)
  end
end
