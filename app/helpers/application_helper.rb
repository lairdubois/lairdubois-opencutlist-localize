module ApplicationHelper
  # Status dot classes, shared by the search bar filters and the translator's editor badges
  STATUS_DOTS = {
    "untranslated" => "border border-stone-400",
    "outdated" => "bg-amber-500",
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
end
