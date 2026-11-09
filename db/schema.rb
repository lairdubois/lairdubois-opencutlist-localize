# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_09_090000) do
  create_table "baselines", force: :cascade do |t|
    t.string "fr_hash"
    t.json "entries"
    t.string "source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "branch_notes"
  end

  create_table "branch_notes", force: :cascade do |t|
    t.string "path", null: false
    t.text "note", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["path"], name: "index_branch_notes_on_path", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.integer "unit_id", null: false
    t.integer "language_id"
    t.integer "user_id", null: false
    t.text "body", null: false
    t.boolean "question", default: false, null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin_only", default: false, null: false
    t.integer "parent_id"
    t.index ["language_id"], name: "index_comments_on_language_id"
    t.index ["parent_id"], name: "index_comments_on_parent_id"
    t.index ["unit_id"], name: "index_comments_on_unit_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "glossary_entries", force: :cascade do |t|
    t.integer "glossary_term_id", null: false
    t.integer "language_id", null: false
    t.string "term"
    t.text "variants"
    t.text "avoid"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["glossary_term_id", "language_id"], name: "index_glossary_entries_on_glossary_term_id_and_language_id", unique: true
    t.index ["glossary_term_id"], name: "index_glossary_entries_on_glossary_term_id"
    t.index ["language_id"], name: "index_glossary_entries_on_language_id"
  end

  create_table "glossary_revisions", force: :cascade do |t|
    t.integer "glossary_term_id", null: false
    t.integer "language_id"
    t.integer "user_id"
    t.string "kind", null: false
    t.json "changes_made"
    t.datetime "created_at", null: false
    t.string "origin"
    t.index ["glossary_term_id"], name: "index_glossary_revisions_on_glossary_term_id"
    t.index ["language_id"], name: "index_glossary_revisions_on_language_id"
    t.index ["user_id"], name: "index_glossary_revisions_on_user_id"
  end

  create_table "glossary_terms", force: :cascade do |t|
    t.string "term", null: false
    t.text "variants"
    t.text "definition"
    t.boolean "no_translate", default: false, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "help_requests", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "language_id"
    t.text "body", null: false
    t.string "page"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["language_id"], name: "index_help_requests_on_language_id"
    t.index ["resolved_at"], name: "index_help_requests_on_resolved_at"
    t.index ["user_id"], name: "index_help_requests_on_user_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "inviter_id"
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["user_id"], name: "index_invitations_on_user_id"
  end

  create_table "issues", force: :cascade do |t|
    t.integer "language_id", null: false
    t.integer "unit_id"
    t.string "kind", null: false
    t.text "body", null: false
    t.text "text"
    t.string "origin"
    t.datetime "closed_at"
    t.integer "closed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["closed_by_id"], name: "index_issues_on_closed_by_id"
    t.index ["language_id", "closed_at"], name: "index_issues_on_language_id_and_closed_at"
    t.index ["language_id"], name: "index_issues_on_language_id"
    t.index ["unit_id"], name: "index_issues_on_unit_id"
  end

  create_table "languages", force: :cascade do |t|
    t.string "code"
    t.string "name"
    t.boolean "rtl", default: false, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "pretranslate_no_translate", default: false, null: false
    t.boolean "compounding", default: false, null: false
    t.index ["code"], name: "index_languages_on_code", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "language_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["language_id"], name: "index_memberships_on_language_id"
    t.index ["user_id", "language_id"], name: "index_memberships_on_user_id_and_language_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "publications", force: :cascade do |t|
    t.string "branch"
    t.string "commit_sha"
    t.string "pr_url"
    t.string "fr_hash"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_publications_on_user_id"
  end

  create_table "revisions", force: :cascade do |t|
    t.integer "unit_id", null: false
    t.integer "language_id"
    t.string "kind", null: false
    t.text "old_value"
    t.text "new_value"
    t.string "author"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["language_id"], name: "index_revisions_on_language_id"
    t.index ["unit_id"], name: "index_revisions_on_unit_id"
    t.index ["user_id"], name: "index_revisions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key"
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "suggestions", force: :cascade do |t|
    t.integer "unit_id", null: false
    t.integer "language_id", null: false
    t.text "text", null: false
    t.string "origin", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source_hash"
    t.index ["language_id"], name: "index_suggestions_on_language_id"
    t.index ["unit_id"], name: "index_suggestions_on_unit_id"
  end

  create_table "translations", force: :cascade do |t|
    t.integer "unit_id", null: false
    t.integer "language_id", null: false
    t.text "text", null: false
    t.integer "status", default: 0, null: false
    t.string "source_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["language_id"], name: "index_translations_on_language_id"
    t.index ["unit_id", "language_id"], name: "index_translations_on_unit_id_and_language_id", unique: true
    t.index ["unit_id"], name: "index_translations_on_unit_id"
  end

  create_table "units", force: :cascade do |t|
    t.string "key", null: false
    t.text "source_text", null: false
    t.string "source_hash"
    t.text "note"
    t.integer "position", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "translatable", default: true, null: false
    t.boolean "copied", default: false, null: false
    t.index ["key"], name: "index_units_on_key", unique: true, where: "archived_at IS NULL"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "github_id"
    t.string "github_login"
    t.text "github_access_token"
    t.datetime "github_token_expires_at"
    t.text "github_refresh_token"
    t.datetime "github_refresh_token_expires_at"
    t.string "locale"
    t.string "reference_language", default: "fr", null: false
    t.datetime "disabled_at"
    t.datetime "last_seen_at"
    t.string "glossary_columns"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["github_id"], name: "index_users_on_github_id", unique: true
  end

  create_table "volunteer_requests", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "language_code", null: false
    t.string "locale"
    t.integer "status", default: 0, null: false
    t.integer "user_id"
    t.integer "handled_by_id"
    t.datetime "handled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["handled_by_id"], name: "index_volunteer_requests_on_handled_by_id"
    t.index ["status"], name: "index_volunteer_requests_on_status"
    t.index ["user_id"], name: "index_volunteer_requests_on_user_id"
  end

  add_foreign_key "comments", "comments", column: "parent_id"
  add_foreign_key "comments", "languages"
  add_foreign_key "comments", "units"
  add_foreign_key "comments", "users"
  add_foreign_key "glossary_entries", "glossary_terms"
  add_foreign_key "glossary_entries", "languages"
  add_foreign_key "glossary_revisions", "glossary_terms"
  add_foreign_key "glossary_revisions", "languages"
  add_foreign_key "glossary_revisions", "users"
  add_foreign_key "help_requests", "languages"
  add_foreign_key "help_requests", "users"
  add_foreign_key "invitations", "users"
  add_foreign_key "invitations", "users", column: "inviter_id", on_delete: :nullify
  add_foreign_key "issues", "languages"
  add_foreign_key "issues", "units"
  add_foreign_key "issues", "users", column: "closed_by_id"
  add_foreign_key "memberships", "languages"
  add_foreign_key "memberships", "users"
  add_foreign_key "publications", "users"
  add_foreign_key "revisions", "languages"
  add_foreign_key "revisions", "units"
  add_foreign_key "revisions", "users"
  add_foreign_key "suggestions", "languages"
  add_foreign_key "suggestions", "units"
  add_foreign_key "translations", "languages"
  add_foreign_key "translations", "units"
  add_foreign_key "volunteer_requests", "users"
  add_foreign_key "volunteer_requests", "users", column: "handled_by_id"
end
