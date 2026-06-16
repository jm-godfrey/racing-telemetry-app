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

ActiveRecord::Schema[8.0].define(version: 2026_06_16_163007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer "priority", default: 0, null: false
    t.integer "attempts", default: 0, null: false
    t.text "handler", null: false
    t.text "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string "locked_by"
    t.string "queue"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["priority", "run_at"], name: "delayed_jobs_priority"
  end

  create_table "laps", force: :cascade do |t|
    t.bigint "race_id", null: false
    t.integer "number", null: false
    t.integer "start_offset_ms", null: false
    t.integer "end_offset_ms", null: false
    t.integer "lap_time_ms", null: false
    t.float "top_speed"
    t.boolean "best", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["race_id", "number"], name: "index_laps_on_race_id_and_number", unique: true
    t.index ["race_id"], name: "index_laps_on_race_id"
  end

  create_table "races", force: :cascade do |t|
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "recorded_at"
    t.integer "duration_ms"
    t.float "start_finish_lat_a"
    t.float "start_finish_lon_a"
    t.float "start_finish_lat_b"
    t.float "start_finish_lon_b"
    t.integer "sample_count", default: 0, null: false
    t.integer "lap_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.string "session_id", null: false
    t.text "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_sessions_on_session_id", unique: true
    t.index ["updated_at"], name: "index_sessions_on_updated_at"
  end

  create_table "telemetry_samples", force: :cascade do |t|
    t.bigint "race_id", null: false
    t.bigint "lap_id"
    t.integer "offset_ms", null: false
    t.integer "sequence", null: false
    t.float "lat"
    t.float "lon"
    t.float "speed"
    t.float "accel_x"
    t.float "accel_y"
    t.float "accel_z"
    t.index ["lap_id"], name: "index_telemetry_samples_on_lap_id"
    t.index ["race_id", "sequence"], name: "index_telemetry_samples_on_race_id_and_sequence"
    t.index ["race_id"], name: "index_telemetry_samples_on_race_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "laps", "races"
  add_foreign_key "telemetry_samples", "laps"
  add_foreign_key "telemetry_samples", "races"
end
