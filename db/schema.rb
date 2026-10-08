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

ActiveRecord::Schema[8.1].define(version: 2026_10_08_120000) do
  create_table "baselines", force: :cascade do |t|
    t.string "fr_hash"
    t.json "entries"
    t.string "source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["language_id"], name: "index_comments_on_language_id"
    t.index ["unit_id"], name: "index_comments_on_unit_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "languages", force: :cascade do |t|
    t.string "code"
    t.string "name"
    t.boolean "rtl", default: false, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["key"], name: "index_units_on_key", unique: true, where: "archived_at IS NULL"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "transifex_username"
    t.bigint "github_id"
    t.string "github_login"
    t.text "github_access_token"
    t.datetime "github_token_expires_at"
    t.text "github_refresh_token"
    t.datetime "github_refresh_token_expires_at"
    t.string "locale"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["github_id"], name: "index_users_on_github_id", unique: true
    t.index ["transifex_username"], name: "index_users_on_transifex_username", unique: true
  end

  add_foreign_key "comments", "languages"
  add_foreign_key "comments", "units"
  add_foreign_key "comments", "users"
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
end
