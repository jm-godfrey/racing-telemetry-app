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

ActiveRecord::Schema[8.0].define(version: 2026_06_16_025913) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  add_foreign_key "telemetry_samples", "races"
end
