module ApplicationHelper
  # Status dot classes, shared by the search bar filters and the translator's editor badges
  STATUS_DOTS = {
    "untranslated" => "border border-stone-400",
    "outdated" => "bg-amber-500",
    "unreviewed" => "bg-sky-500",
    "reviewed" => "bg-emerald-500"
  }.freeze

  def status_dot(status, extra = nil)
    tag.span(class: ["h-2 w-2 shrink-0 rounded-full", STATUS_DOTS[status], extra])
  end
end
