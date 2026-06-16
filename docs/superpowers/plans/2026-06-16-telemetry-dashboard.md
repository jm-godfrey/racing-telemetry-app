# Racing Telemetry Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user upload a race-telemetry CSV, see the GPS racing line drawn on a speed-coloured map, click a start/finish line, and get auto-detected, timed laps in a table.

**Architecture:** One uploaded CSV = one `Race`. A background job parses rows into `TelemetrySample` records. The user draws a start/finish line on the map; a second job runs the pure-logic `LapDetector` (segment-crossing) to build timed `Lap` records. The race page renders the path on a `<canvas>` (abstract plot, speed-coloured) with a lap table beneath it.

**Tech Stack:** Rails 8, PostgreSQL, Active Record, Active Storage (CSV file), Delayed Job (background), Hamlit (Haml views), simple_form + Bootstrap 5, Shakapacker (plain JS module on `<canvas>`), RSpec + FactoryBot + Capybara/headless-Chrome.

**Conventions in this repo (don't fight them):**
- Views are `.haml`, not ERB. Forms use `simple_form`.
- Background jobs use `:delayed_job` (`config.active_job.queue_adapter`). Use `SomeJob.perform_later`.
- Specs: `create`/`build` are unprefixed (FactoryBot). `js: true` specs use headless Chrome and DatabaseCleaner truncation.
- Run a single spec: `bundle exec rspec path/to/spec.rb`. Full suite: `bundle exec rake`.
- After adding/altering a model, optionally refresh annotations: `bundle exec annotaterb models`.

---

## File structure

**Models** (`app/models/`)
- `race.rb` — the session/upload. Status enum, start/finish coords, `has_one_attached :csv_file`, associations.
- `telemetry_sample.rb` — one CSV row.
- `lap.rb` — one detected lap.

**Services** (`app/services/`) — pure, DB-free where possible
- `csv_telemetry_parser.rb` — CSV file/IO → array of row hashes; validates headers.
- `lap_detector.rb` — ordered points + start/finish segment → array of lap hashes (segment-crossing math).

**Jobs** (`app/jobs/`)
- `parse_race_job.rb` — parse CSV, bulk-insert samples, set race stats/status.
- `detect_laps_job.rb` — run `LapDetector`, persist `Lap`s, tag samples, flag best.

**Controllers / routes**
- `app/controllers/races_controller.rb` — index, new, create, show, destroy, start_finish.
- `config/routes.rb` — `resources :races` (subset) + member `start_finish`.

**Views** (`app/views/races/`) — `index.html.haml`, `new.html.haml`, `show.html.haml`, `_lap_table.html.haml`.

**Front-end** (`app/packs/scripts/track_map.js`, imported from `app/packs/entrypoints/application.js`).

**Specs** mirror the above under `spec/`. Fixture CSV at `spec/factories/files/telemetry_sample.csv`.

---

## Task 1: Race model, migration, factory

**Files:**
- Create: `db/migrate/<ts>_create_races.rb` (via generator)
- Create: `app/models/race.rb`
- Create: `spec/factories/races.rb`
- Test: `spec/models/race_spec.rb`

- [ ] **Step 1: Generate the migration**

Run:
```bash
bin/rails g migration CreateRaces
```

Replace the generated migration body with:
```ruby
class CreateRaces < ActiveRecord::Migration[8.0]
  def change
    create_table :races do |t|
      t.string  :name, null: false
      t.integer :status, null: false, default: 0
      t.datetime :recorded_at
      t.integer :duration_ms
      t.float :start_finish_lat_a
      t.float :start_finish_lon_a
      t.float :start_finish_lat_b
      t.float :start_finish_lon_b
      t.integer :sample_count, null: false, default: 0
      t.integer :lap_count, null: false, default: 0
      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`
Expected: `create_table(:races)` succeeds.

- [ ] **Step 3: Write the model**

`app/models/race.rb`:
```ruby
class Race < ApplicationRecord
  has_one_attached :csv_file

  has_many :telemetry_samples, dependent: :delete_all
  has_many :laps, dependent: :delete_all

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  validates :name, presence: true

  # True once the user has placed all four start/finish coordinates.
  def start_finish_set?
    [start_finish_lat_a, start_finish_lon_a,
     start_finish_lat_b, start_finish_lon_b].all?(&:present?)
  end

  def best_lap
    laps.find_by(best: true)
  end
end
```

- [ ] **Step 4: Write the factory**

`spec/factories/races.rb`:
```ruby
FactoryBot.define do
  factory :race do
    sequence(:name) { |n| "Race #{n}" }
    status { :pending }

    trait :with_csv do
      after(:build) do |race|
        race.csv_file.attach(
          io: File.open(Rails.root.join("spec/factories/files/telemetry_sample.csv")),
          filename: "telemetry_sample.csv",
          content_type: "text/csv"
        )
      end
    end
  end
end
```

- [ ] **Step 5: Write the model spec**

`spec/models/race_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Race do
  it "requires a name" do
    expect(build(:race, name: nil)).not_to be_valid
  end

  it "defaults to pending status" do
    expect(build(:race).status).to eq("pending")
  end

  describe "#start_finish_set?" do
    it "is false when coordinates are missing" do
      expect(build(:race).start_finish_set?).to be(false)
    end

    it "is true when all four coordinates are present" do
      race = build(:race, start_finish_lat_a: 1, start_finish_lon_a: 2,
                          start_finish_lat_b: 3, start_finish_lon_b: 4)
      expect(race.start_finish_set?).to be(true)
    end
  end
end
```

- [ ] **Step 6: Create the fixture CSV** (used by `:with_csv` and later tasks)

`spec/factories/files/telemetry_sample.csv`:
```csv
timestamp,lat,lon,speed,accelX,accelY,accelZ
1000,0,0,0,0,0,1
1100,53.0,-1.0,5.0,0.1,0.1,0.98
1200,53.0001,-1.0,10.0,0.2,0.1,0.98
1300,53.0002,-1.0,12.0,0.2,0.2,0.98
1400,53.0003,-1.0,8.0,0.1,0.2,0.98
```

- [ ] **Step 7: Run the spec**

Run: `bundle exec rspec spec/models/race_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 8: Commit**

```bash
git add app/models/race.rb db/migrate db/schema.rb spec/factories/races.rb spec/factories/files/telemetry_sample.csv spec/models/race_spec.rb
git commit -m "Add Race model"
```

---

## Task 2: TelemetrySample model, migration, factory

**Files:**
- Create: `db/migrate/<ts>_create_telemetry_samples.rb`
- Create: `app/models/telemetry_sample.rb`
- Create: `spec/factories/telemetry_samples.rb`
- Test: `spec/models/telemetry_sample_spec.rb`

Note: `lap_id` is a nullable column with an index but **no DB foreign key** (avoids migration-ordering coupling; the Rails association is enough). No `timestamps` — samples are immutable bulk data, which keeps `insert_all` simple.

- [ ] **Step 1: Generate + edit migration**

Run: `bin/rails g migration CreateTelemetrySamples`

Body:
```ruby
class CreateTelemetrySamples < ActiveRecord::Migration[8.0]
  def change
    create_table :telemetry_samples do |t|
      t.references :race, null: false, foreign_key: true
      t.bigint  :lap_id
      t.integer :offset_ms, null: false
      t.integer :sequence, null: false
      t.float :lat
      t.float :lon
      t.float :speed
      t.float :accel_x
      t.float :accel_y
      t.float :accel_z
    end
    add_index :telemetry_samples, [:race_id, :sequence]
    add_index :telemetry_samples, :lap_id
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`
Expected: success.

- [ ] **Step 3: Write the model**

`app/models/telemetry_sample.rb`:
```ruby
class TelemetrySample < ApplicationRecord
  belongs_to :race
  belongs_to :lap, optional: true

  # A sample has a usable GPS fix once lat/lon are not both zero
  # (the leading "warm-up" rows are 0,0 before the GPS locks).
  scope :located, -> { where.not(lat: 0, lon: 0) }
end
```

- [ ] **Step 4: Write the factory**

`spec/factories/telemetry_samples.rb`:
```ruby
FactoryBot.define do
  factory :telemetry_sample do
    race
    sequence(:sequence) { |n| n }
    offset_ms { sequence * 100 }
    lat { 53.0 }
    lon { -1.0 }
    speed { 10.0 }
    accel_x { 0.1 }
    accel_y { 0.1 }
    accel_z { 0.98 }
  end
end
```

- [ ] **Step 5: Write the spec**

`spec/models/telemetry_sample_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe TelemetrySample do
  it "belongs to a race" do
    expect(build(:telemetry_sample).race).to be_present
  end

  describe ".located" do
    it "excludes warm-up rows at 0,0" do
      race = create(:race)
      good = create(:telemetry_sample, race: race, lat: 53.0, lon: -1.0)
      create(:telemetry_sample, race: race, lat: 0, lon: 0)
      expect(race.telemetry_samples.located).to contain_exactly(good)
    end
  end
end
```

- [ ] **Step 6: Run + commit**

Run: `bundle exec rspec spec/models/telemetry_sample_spec.rb` → PASS (2 examples).
```bash
git add app/models/telemetry_sample.rb db/migrate db/schema.rb spec/factories/telemetry_samples.rb spec/models/telemetry_sample_spec.rb
git commit -m "Add TelemetrySample model"
```

---

## Task 3: Lap model, migration, factory

**Files:**
- Create: `db/migrate/<ts>_create_laps.rb`
- Create: `app/models/lap.rb`
- Create: `spec/factories/laps.rb`
- Test: `spec/models/lap_spec.rb`

- [ ] **Step 1: Generate + edit migration**

Run: `bin/rails g migration CreateLaps`

Body:
```ruby
class CreateLaps < ActiveRecord::Migration[8.0]
  def change
    create_table :laps do |t|
      t.references :race, null: false, foreign_key: true
      t.integer :number, null: false
      t.integer :start_offset_ms, null: false
      t.integer :end_offset_ms, null: false
      t.integer :lap_time_ms, null: false
      t.float :top_speed
      t.boolean :best, null: false, default: false
      t.timestamps
    end
    add_index :laps, [:race_id, :number], unique: true
  end
end
```

- [ ] **Step 2: Migrate** → `bin/rails db:migrate`

- [ ] **Step 3: Write the model**

`app/models/lap.rb`:
```ruby
class Lap < ApplicationRecord
  belongs_to :race
  has_many :telemetry_samples, dependent: :nullify

  validates :number, :start_offset_ms, :end_offset_ms, :lap_time_ms, presence: true

  def formatted_time
    total_seconds = lap_time_ms / 1000.0
    minutes = (total_seconds / 60).floor
    seconds = total_seconds - minutes * 60
    format("%d:%06.3f", minutes, seconds)
  end
end
```

- [ ] **Step 4: Write the factory**

`spec/factories/laps.rb`:
```ruby
FactoryBot.define do
  factory :lap do
    race
    sequence(:number) { |n| n }
    start_offset_ms { 0 }
    end_offset_ms { 90_000 }
    lap_time_ms { 90_000 }
    top_speed { 120.0 }
    best { false }
  end
end
```

- [ ] **Step 5: Write the spec**

`spec/models/lap_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Lap do
  describe "#formatted_time" do
    it "renders milliseconds as M:SS.mmm" do
      expect(build(:lap, lap_time_ms: 101_234).formatted_time).to eq("1:41.234")
    end

    it "renders sub-minute laps" do
      expect(build(:lap, lap_time_ms: 5_678).formatted_time).to eq("0:05.678")
    end
  end
end
```

- [ ] **Step 6: Run + commit**

Run: `bundle exec rspec spec/models/lap_spec.rb` → PASS (2 examples).
```bash
git add app/models/lap.rb db/migrate db/schema.rb spec/factories/laps.rb spec/models/lap_spec.rb
git commit -m "Add Lap model"
```

---

## Task 4: CsvTelemetryParser service

Turns a CSV file/IO into an array of row hashes with numeric values. Validates the header. Knows nothing about the database.

**Files:**
- Create: `app/services/csv_telemetry_parser.rb`
- Test: `spec/services/csv_telemetry_parser_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/services/csv_telemetry_parser_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe CsvTelemetryParser do
  let(:csv) do
    <<~CSV
      timestamp,lat,lon,speed,accelX,accelY,accelZ
      1000,0,0,0,0,0,1
      1100,53.0,-1.0,5.0,0.1,0.2,0.98
    CSV
  end

  it "parses each row into a numeric hash" do
    rows = described_class.new(StringIO.new(csv)).rows
    expect(rows.length).to eq(2)
    expect(rows.first).to eq(
      timestamp: 1000, lat: 0.0, lon: 0.0, speed: 0.0,
      accel_x: 0.0, accel_y: 0.0, accel_z: 1.0
    )
    expect(rows.last[:lat]).to eq(53.0)
  end

  it "raises on a missing required header" do
    bad = "timestamp,lat,lon\n1000,0,0\n"
    expect { described_class.new(StringIO.new(bad)).rows }
      .to raise_error(CsvTelemetryParser::InvalidFormat, /missing/i)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/services/csv_telemetry_parser_spec.rb`
Expected: FAIL — `uninitialized constant CsvTelemetryParser`.

- [ ] **Step 3: Implement**

`app/services/csv_telemetry_parser.rb`:
```ruby
require "csv"

class CsvTelemetryParser
  class InvalidFormat < StandardError; end

  # CSV header name => symbol we store it under.
  COLUMN_MAP = {
    "timestamp" => :timestamp,
    "lat" => :lat,
    "lon" => :lon,
    "speed" => :speed,
    "accelX" => :accel_x,
    "accelY" => :accel_y,
    "accelZ" => :accel_z
  }.freeze

  REQUIRED_HEADERS = COLUMN_MAP.keys.freeze

  def initialize(io)
    @io = io
  end

  def rows
    table = CSV.new(@io, headers: true, header_converters: ->(h) { h.strip })
    parsed = table.read
    validate_headers!(parsed.headers)

    parsed.map do |row|
      COLUMN_MAP.each_with_object({}) do |(header, key), out|
        out[key] = key == :timestamp ? row[header].to_i : row[header].to_f
      end
    end
  end

  private

  def validate_headers!(headers)
    missing = REQUIRED_HEADERS - headers
    return if missing.empty?

    raise InvalidFormat, "CSV is missing required columns: #{missing.join(', ')}"
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/services/csv_telemetry_parser_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/csv_telemetry_parser.rb spec/services/csv_telemetry_parser_spec.rb
git commit -m "Add CsvTelemetryParser"
```

---

## Task 5: ParseRaceJob

Reads the attached CSV, parses it, bulk-inserts samples (offsets relative to the first timestamp), and fills in race stats + status. On failure, marks the race `failed`.

**Files:**
- Create: `app/jobs/parse_race_job.rb`
- Test: `spec/jobs/parse_race_job_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/jobs/parse_race_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe ParseRaceJob do
  let(:race) { create(:race, :with_csv) }

  it "creates one sample per CSV row with offsets from the first timestamp" do
    ParseRaceJob.perform_now(race.id)
    race.reload

    expect(race.telemetry_samples.count).to eq(5)
    first = race.telemetry_samples.order(:sequence).first
    expect(first.offset_ms).to eq(0)
    expect(race.telemetry_samples.order(:sequence).last.offset_ms).to eq(400)
  end

  it "marks the race ready and records stats" do
    ParseRaceJob.perform_now(race.id)
    race.reload

    expect(race).to be_ready
    expect(race.sample_count).to eq(5)
    expect(race.duration_ms).to eq(400)
  end

  it "marks the race failed when the CSV is malformed" do
    bad = create(:race)
    bad.csv_file.attach(io: StringIO.new("nope\n1\n"), filename: "bad.csv", content_type: "text/csv")
    ParseRaceJob.perform_now(bad.id)
    expect(bad.reload).to be_failed
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/jobs/parse_race_job_spec.rb`
Expected: FAIL — `uninitialized constant ParseRaceJob`.

- [ ] **Step 3: Implement**

`app/jobs/parse_race_job.rb`:
```ruby
class ParseRaceJob < ApplicationJob
  queue_as :default

  def perform(race_id)
    race = Race.find(race_id)
    race.processing!

    rows = race.csv_file.open { |file| CsvTelemetryParser.new(file).rows }
    raise CsvTelemetryParser::InvalidFormat, "no rows" if rows.empty?

    first_ts = rows.first[:timestamp]
    records = rows.each_with_index.map do |row, i|
      {
        race_id: race.id,
        sequence: i,
        offset_ms: row[:timestamp] - first_ts,
        lat: row[:lat], lon: row[:lon], speed: row[:speed],
        accel_x: row[:accel_x], accel_y: row[:accel_y], accel_z: row[:accel_z]
      }
    end

    TelemetrySample.insert_all(records)

    race.update!(
      status: :ready,
      sample_count: records.length,
      duration_ms: rows.last[:timestamp] - first_ts,
      recorded_at: Time.zone.at(first_ts / 1000.0)
    )
  rescue StandardError => e
    Rails.logger.error("ParseRaceJob failed for race #{race_id}: #{e.message}")
    race&.failed!
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/jobs/parse_race_job_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add app/jobs/parse_race_job.rb spec/jobs/parse_race_job_spec.rb
git commit -m "Add ParseRaceJob"
```

---

## Task 6: LapDetector service (the core logic)

Pure logic. Given ordered located points and a start/finish line segment, it finds each crossing (proper segment intersection), interpolates the exact crossing time, and returns the laps *between* consecutive crossings. The out-lap (before the first crossing) and in-lap (after the last) are dropped. Points with `0,0` GPS are filtered out defensively.

Coordinate note: over a small area we treat `lon` as x and `lat` as y directly — fine for crossing-detection sign tests.

**Files:**
- Create: `app/services/lap_detector.rb`
- Test: `spec/services/lap_detector_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/services/lap_detector_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe LapDetector do
  # Start/finish line: a vertical segment at lon(x)=0, lat(y) from -1..1.
  let(:line) { { lat_a: -1.0, lon_a: 0.0, lat_b: 1.0, lon_b: 0.0 } }

  # Path crosses the line three times (=> two laps), each 2000 ms apart.
  # Points are {offset_ms:, lat:(y), lon:(x)}.
  let(:samples) do
    [
      { offset_ms: 0,    lat: 0.0, lon: -1.0 },
      { offset_ms: 1000, lat: 0.0, lon:  1.0 }, # cross #1 at t=500
      { offset_ms: 2000, lat: 0.5, lon:  1.0 },
      { offset_ms: 3000, lat: 0.5, lon: -1.0 }, # cross #2 at t=2500
      { offset_ms: 4000, lat: 0.0, lon: -1.0 },
      { offset_ms: 5000, lat: 0.0, lon:  1.0 }  # cross #3 at t=4500
    ]
  end

  it "detects laps between consecutive crossings" do
    laps = described_class.new(samples, **line).laps
    expect(laps.length).to eq(2)
    expect(laps.map { |l| l[:number] }).to eq([1, 2])
    expect(laps.map { |l| l[:lap_time_ms] }).to eq([2000, 2000])
    expect(laps.first).to include(start_offset_ms: 500, end_offset_ms: 2500)
  end

  it "returns no laps when the path never crosses the line" do
    away = samples.map { |s| s.merge(lon: s[:lon] + 100) }
    expect(described_class.new(away, **line).laps).to be_empty
  end

  it "ignores warm-up points at 0,0" do
    with_warmup = [{ offset_ms: -100, lat: 0.0, lon: 0.0 }] + samples
    laps = described_class.new(with_warmup, **line).laps
    expect(laps.length).to eq(2)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/services/lap_detector_spec.rb`
Expected: FAIL — `uninitialized constant LapDetector`.

- [ ] **Step 3: Implement**

`app/services/lap_detector.rb`:
```ruby
class LapDetector
  Point = Struct.new(:x, :y, :t)

  def initialize(samples, lat_a:, lon_a:, lat_b:, lon_b:)
    @points = samples
      .reject { |s| s[:lat].to_f.zero? && s[:lon].to_f.zero? }
      .map { |s| Point.new(s[:lon].to_f, s[:lat].to_f, s[:offset_ms]) }
    @a = Point.new(lon_a.to_f, lat_a.to_f, nil)
    @b = Point.new(lon_b.to_f, lat_b.to_f, nil)
  end

  # => [{ number:, start_offset_ms:, end_offset_ms:, lap_time_ms: }, ...]
  def laps
    crossings = crossing_times
    crossings.each_cons(2).with_index(1).map do |(start_t, end_t), number|
      {
        number: number,
        start_offset_ms: start_t,
        end_offset_ms: end_t,
        lap_time_ms: end_t - start_t
      }
    end
  end

  private

  def crossing_times
    times = []
    @points.each_cons(2) do |p1, p2|
      next unless segments_intersect?(p1, p2, @a, @b)

      times << interpolate_time(p1, p2)
    end
    times
  end

  # Proper segment intersection via orientation tests.
  def segments_intersect?(p1, p2, p3, p4)
    d1 = direction(p3, p4, p1)
    d2 = direction(p3, p4, p2)
    d3 = direction(p1, p2, p3)
    d4 = direction(p1, p2, p4)
    ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
  end

  def direction(a, b, c)
    (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y)
  end

  # Fraction along p1->p2 where it crosses line A-B, then lerp the timestamp.
  def interpolate_time(p1, p2)
    r = [p2.x - p1.x, p2.y - p1.y]
    s = [@b.x - @a.x, @b.y - @a.y]
    denom = cross(r, s)
    return p1.t if denom.zero?

    qp = [@a.x - p1.x, @a.y - p1.y]
    t = cross(qp, s) / denom
    (p1.t + t * (p2.t - p1.t)).round
  end

  def cross(u, v)
    u[0] * v[1] - u[1] * v[0]
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/services/lap_detector_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/lap_detector.rb spec/services/lap_detector_spec.rb
git commit -m "Add LapDetector"
```

---

## Task 7: DetectLapsJob

Loads the race's located samples, runs `LapDetector`, persists `Lap` records, tags each sample with its `lap_id`, flags the fastest as `best`, and updates `race.lap_count`.

**Files:**
- Create: `app/jobs/detect_laps_job.rb`
- Test: `spec/jobs/detect_laps_job_spec.rb`

- [ ] **Step 1: Write the failing spec**

`spec/jobs/detect_laps_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe DetectLapsJob do
  let(:race) do
    create(:race,
           start_finish_lat_a: -1.0, start_finish_lon_a: 0.0,
           start_finish_lat_b: 1.0,  start_finish_lon_b: 0.0)
  end

  # Same geometry as the LapDetector spec: 3 crossings => 2 laps.
  before do
    coords = [
      [0,    0.0, -1.0], [1000, 0.0, 1.0], [2000, 0.5, 1.0],
      [3000, 0.5, -1.0], [4000, 0.0, -1.0], [5000, 0.0, 1.0]
    ]
    coords.each_with_index do |(t, lat, lon), i|
      create(:telemetry_sample, race: race, sequence: i, offset_ms: t,
                                lat: lat, lon: lon, speed: 10 + i)
    end
  end

  it "creates a Lap per detected lap and updates the race count" do
    DetectLapsJob.perform_now(race.id)
    expect(race.reload.laps.count).to eq(2)
    expect(race.lap_count).to eq(2)
  end

  it "flags the fastest lap as best" do
    DetectLapsJob.perform_now(race.id)
    expect(race.laps.where(best: true).count).to eq(1)
  end

  it "tags samples that fall inside a lap with its lap_id" do
    DetectLapsJob.perform_now(race.id)
    lap = race.laps.find_by(number: 1)
    tagged = race.telemetry_samples.where(lap_id: lap.id)
    expect(tagged).to be_present
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/jobs/detect_laps_job_spec.rb`
Expected: FAIL — `uninitialized constant DetectLapsJob`.

- [ ] **Step 3: Implement**

`app/jobs/detect_laps_job.rb`:
```ruby
class DetectLapsJob < ApplicationJob
  queue_as :default

  def perform(race_id)
    race = Race.find(race_id)
    return unless race.start_finish_set?

    samples = race.telemetry_samples.located.order(:sequence)
                  .pluck(:offset_ms, :lat, :lon)
                  .map { |o, la, lo| { offset_ms: o, lat: la, lon: lo } }

    detected = LapDetector.new(
      samples,
      lat_a: race.start_finish_lat_a, lon_a: race.start_finish_lon_a,
      lat_b: race.start_finish_lat_b, lon_b: race.start_finish_lon_b
    ).laps

    Race.transaction do
      race.laps.delete_all
      race.telemetry_samples.update_all(lap_id: nil)

      created = detected.map do |lap|
        record = race.laps.create!(
          number: lap[:number],
          start_offset_ms: lap[:start_offset_ms],
          end_offset_ms: lap[:end_offset_ms],
          lap_time_ms: lap[:lap_time_ms]
        )
        race.telemetry_samples
            .where(offset_ms: lap[:start_offset_ms]..lap[:end_offset_ms])
            .update_all(lap_id: record.id)
        record.update!(top_speed: record.telemetry_samples.maximum(:speed))
        record
      end

      created.min_by(&:lap_time_ms)&.update!(best: true)
      race.update!(lap_count: created.length)
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/jobs/detect_laps_job_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add app/jobs/detect_laps_job.rb spec/jobs/detect_laps_job_spec.rb
git commit -m "Add DetectLapsJob"
```

---

## Task 8: Routes, RacesController, and views (index / new / create / show / destroy)

Wires upload + listing + the race page shell. The map canvas and lap table get filled in by Tasks 10–12; here the show page just renders the container and a placeholder.

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/races_controller.rb`
- Create: `app/views/races/index.html.haml`, `new.html.haml`, `show.html.haml`
- Test: `spec/requests/races_spec.rb`

- [ ] **Step 1: Add routes**

Edit `config/routes.rb` — inside the `Rails.application.routes.draw` block, above `root`:
```ruby
  resources :races, only: %i[index new create show destroy] do
    member do
      patch :start_finish
    end
  end
```

- [ ] **Step 2: Write the failing request spec**

`spec/requests/races_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Races", type: :request do
  it "lists races on the index" do
    create(:race, name: "Brands Hatch AM")
    get races_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Brands Hatch AM")
  end

  it "renders the upload form" do
    get new_race_path
    expect(response).to have_http_status(:ok)
  end

  it "creates a race from an uploaded CSV and enqueues parsing" do
    file = fixture_file_upload("telemetry_sample.csv", "text/csv")
    expect {
      post races_path, params: { race: { csv_file: file } }
    }.to change(Race, :count).by(1)
    expect(ParseRaceJob).to have_been_enqueued
    expect(response).to redirect_to(race_path(Race.last))
    expect(Race.last.name).to eq("telemetry_sample.csv")
  end

  it "shows a race" do
    race = create(:race)
    get race_path(race)
    expect(response).to have_http_status(:ok)
  end

  it "destroys a race" do
    race = create(:race)
    expect { delete race_path(race) }.to change(Race, :count).by(-1)
    expect(response).to redirect_to(races_path)
  end
end
```

Note: `fixture_file_upload` resolves from `spec/factories/files` (per repo config). Add `config.include ActiveJob::TestHelper, type: :request` is not needed — `have_been_enqueued` works with the `:test` adapter. Ensure the top of the spec has access: add `before { ActiveJob::Base.queue_adapter = :test }` inside the spec if the suite default isn't `:test`.

- [ ] **Step 3: Run to verify it fails**

Run: `bundle exec rspec spec/requests/races_spec.rb`
Expected: FAIL — uninitialized constant / missing route.

- [ ] **Step 4: Implement the controller**

`app/controllers/races_controller.rb`:
```ruby
class RacesController < ApplicationController
  before_action :set_race, only: %i[show destroy start_finish]

  def index
    @races = Race.order(created_at: :desc)
  end

  def new
    @race = Race.new
  end

  def create
    file = params.dig(:race, :csv_file)
    @race = Race.new(name: file&.original_filename || "Untitled race")
    @race.csv_file.attach(file) if file

    if file && @race.save
      ParseRaceJob.perform_later(@race.id)
      redirect_to @race, notice: "Race uploaded. Parsing telemetry…"
    else
      @race.errors.add(:csv_file, "is required") if file.blank?
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @samples_json = @race.telemetry_samples.order(:sequence)
                         .pluck(:offset_ms, :lat, :lon, :speed, :lap_id)
                         .map { |t, lat, lon, sp, lap| { t:, lat:, lon:, sp:, lap: } }
    @laps = @race.laps.order(:number)
  end

  def destroy
    @race.destroy
    redirect_to races_path, notice: "Race deleted."
  end

  def start_finish
    @race.update!(start_finish_params)
    DetectLapsJob.perform_later(@race.id)
    redirect_to @race, notice: "Start/finish line set. Detecting laps…"
  end

  private

  def set_race
    @race = Race.find(params[:id])
  end

  def start_finish_params
    params.require(:race).permit(
      :start_finish_lat_a, :start_finish_lon_a,
      :start_finish_lat_b, :start_finish_lon_b
    )
  end
end
```

- [ ] **Step 5: Create the views**

`app/views/races/index.html.haml`:
```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1 Races
  = link_to "Upload race", new_race_path, class: "btn btn-primary"

- if @races.any?
  %table.table
    %thead
      %tr
        %th Name
        %th Status
        %th Laps
        %th
    %tbody
      - @races.each do |race|
        %tr
          %td= link_to race.name, race
          %td= race.status.titleize
          %td= race.lap_count
          %td= link_to "Delete", race, data: { turbo_method: :delete, turbo_confirm: "Delete this race?" }, class: "text-danger"
- else
  %p.text-muted No races yet. Upload a CSV to get started.
```

`app/views/races/new.html.haml`:
```haml
%h1 Upload race
= simple_form_for @race, url: races_path, html: { multipart: true } do |f|
  = f.input :csv_file, as: :file, label: "Telemetry CSV"
  = f.button :submit, "Upload"
= link_to "Back", races_path
```

`app/views/races/show.html.haml`:
```haml
%h1= @race.name
%p.text-muted Status: #{@race.status.titleize} · #{@race.sample_count} samples

#track-map{ data: { track_map: true,
                    race_id: @race.id,
                    samples: @samples_json.to_json,
                    start_finish: { lat_a: @race.start_finish_lat_a, lon_a: @race.start_finish_lon_a, lat_b: @race.start_finish_lat_b, lon_b: @race.start_finish_lon_b }.to_json,
                    update_url: start_finish_race_path(@race) } }
  %canvas.track-canvas{ width: 900, height: 480 }
  %button#set-start-finish.btn.btn-outline-primary.mt-2{ type: "button" } Set start/finish line

= render "lap_table", race: @race, laps: @laps

= link_to "Back to races", races_path
```

Note: the `#set-start-finish` button and `_lap_table` partial behaviours are implemented in Tasks 11–12; this renders the static shell.

- [ ] **Step 6: Add a minimal lap table partial** (so `show` renders now; enhanced in Task 12)

`app/views/races/_lap_table.html.haml`:
```haml
%h2.mt-4 Laps
- if laps.any?
  %table.table.lap-table
    %thead
      %tr
        %th Lap
        %th Time
        %th Top speed
    %tbody
      - laps.each do |lap|
        %tr{ class: ("table-success" if lap.best), data: { lap_id: lap.id } }
          %td= lap.number
          %td= lap.formatted_time
          %td= lap.top_speed&.round(1)
- else
  %p.text-muted No laps yet. Set the start/finish line on the map to detect laps.
```

- [ ] **Step 7: Run to verify it passes**

Run: `bundle exec rspec spec/requests/races_spec.rb`
Expected: PASS (5 examples).

- [ ] **Step 8: Add a nav link + commit** (optional nav)

Optionally add to `app/views/layouts/application.html.haml` nav: `= link_to "Races", races_path, class: "nav-link"`.

```bash
git add config/routes.rb app/controllers/races_controller.rb app/views/races spec/requests/races_spec.rb
git commit -m "Add races controller, routes and views"
```

---

## Task 9: Make the root route the races index (small UX wire-up)

**Files:**
- Modify: `config/routes.rb`
- Test: extend `spec/requests/races_spec.rb`

- [ ] **Step 1: Add a failing expectation**

Append to `spec/requests/races_spec.rb` inside the top-level describe:
```ruby
  it "uses the races index as the root page" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Races")
  end
```

- [ ] **Step 2: Run → fails** (root still points at `pages#home`)

Run: `bundle exec rspec spec/requests/races_spec.rb -e "root page"`
Expected: FAIL.

- [ ] **Step 3: Repoint root**

In `config/routes.rb` change:
```ruby
  root "races#index"
```
(Remove or keep `pages#home`; the `pages_controller` can stay unused.)

- [ ] **Step 4: Run → passes**, then commit.

```bash
git add config/routes.rb spec/requests/races_spec.rb
git commit -m "Point root route at races index"
```

---

## Task 10: Failing end-to-end feature spec (drives the front-end)

This `js: true` spec describes the full journey and will fail until Tasks 11–12 build the canvas + lap interaction. It uses headless Chrome (already configured) and Active Job inline so the jobs run during the request.

**Files:**
- Create: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Write the spec**

`spec/features/race_telemetry_spec.rb`:
```ruby
require "rails_helper"

RSpec.feature "Race telemetry", js: true do
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  scenario "uploading a CSV draws the map and detecting laps fills the table" do
    visit new_race_path
    attach_file "Telemetry CSV", Rails.root.join("spec/factories/files/telemetry_sample.csv")
    click_button "Upload"

    # Parsing ran inline; the canvas should be present and the page ready.
    expect(page).to have_css("canvas.track-canvas")
    expect(page).to have_content("Ready")

    # No laps until the start/finish line is set.
    expect(page).to have_content("No laps yet")
  end
end
```

Note: this fixture has only 5 points and does not loop, so it won't auto-produce laps via UI clicks reliably; this spec asserts the **map renders** and the **empty-lap state**. Lap-detection logic itself is fully covered by `LapDetector`/`DetectLapsJob` specs. Keep the feature spec focused on wiring.

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb`
Expected: FAIL — no `canvas.track-canvas` drawn / JS not wired yet (canvas element exists from Task 8 but is empty; the failing assertion will be on content/interaction once we add behaviour). If it passes trivially at this point, proceed — Task 11 still adds the rendering behaviour.

- [ ] **Step 3: Commit the spec**

```bash
git add spec/features/race_telemetry_spec.rb
git commit -m "Add end-to-end race telemetry feature spec"
```

---

## Task 11: Track map JS module (render path, colour by speed, click-to-set-line)

Plain JS module on `<canvas>`. Reads `data-samples` (offset/lat/lon/speed/lap), projects lat/lon to canvas pixels, colours each segment by speed (red→amber→green), draws an existing start/finish line, and lets the user click two points to set a new one (submitted via a generated form, standard Rails redirect).

**Files:**
- Create: `app/packs/scripts/track_map.js`
- Modify: `app/packs/entrypoints/application.js`
- Modify: `app/packs/styles/` (one small SCSS file) + import — optional styling
- Validated by: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Implement the module**

`app/packs/scripts/track_map.js`:
```js
// Draws a telemetry racing line on a <canvas>, coloured by speed,
// and supports click-to-set the start/finish line.
function speedColor(speed, min, max) {
  const ratio = max > min ? (speed - min) / (max - min) : 0;
  // red (slow) -> amber -> green (fast)
  const hue = ratio * 120; // 0=red, 120=green
  return `hsl(${hue}, 80%, 50%)`;
}

class TrackMap {
  constructor(root) {
    this.root = root;
    this.canvas = root.querySelector("canvas.track-canvas");
    this.ctx = this.canvas.getContext("2d");
    this.samples = JSON.parse(root.dataset.samples || "[]")
      .filter((s) => !(s.lat === 0 && s.lon === 0));
    this.startFinish = JSON.parse(root.dataset.startFinish || "{}");
    this.updateUrl = root.dataset.updateUrl;
    this.placing = [];
    this.computeBounds();
    this.draw();
    this.bindPlacement();
  }

  computeBounds() {
    const lats = this.samples.map((s) => s.lat);
    const lons = this.samples.map((s) => s.lon);
    this.minLat = Math.min(...lats); this.maxLat = Math.max(...lats);
    this.minLon = Math.min(...lons); this.maxLon = Math.max(...lons);
    this.pad = 30;
  }

  project(lat, lon) {
    const w = this.canvas.width - this.pad * 2;
    const h = this.canvas.height - this.pad * 2;
    const lonSpan = (this.maxLon - this.minLon) || 1;
    const latSpan = (this.maxLat - this.minLat) || 1;
    const x = this.pad + ((lon - this.minLon) / lonSpan) * w;
    // invert y: higher lat = up
    const y = this.pad + (1 - (lat - this.minLat) / latSpan) * h;
    return [x, y];
  }

  unproject(x, y) {
    const w = this.canvas.width - this.pad * 2;
    const h = this.canvas.height - this.pad * 2;
    const lon = this.minLon + ((x - this.pad) / w) * (this.maxLon - this.minLon);
    const lat = this.minLat + (1 - (y - this.pad) / h) * (this.maxLat - this.minLat);
    return [lat, lon];
  }

  draw() {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    if (this.samples.length < 2) return;

    const speeds = this.samples.map((s) => s.sp);
    const min = Math.min(...speeds), max = Math.max(...speeds);

    ctx.lineWidth = 5;
    ctx.lineCap = "round";
    for (let i = 1; i < this.samples.length; i++) {
      const a = this.samples[i - 1], b = this.samples[i];
      const [x1, y1] = this.project(a.lat, a.lon);
      const [x2, y2] = this.project(b.lat, b.lon);
      ctx.strokeStyle = speedColor(b.sp, min, max);
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }
    this.drawStartFinish();
  }

  drawStartFinish() {
    const sf = this.startFinish;
    if (sf.lat_a == null || sf.lat_b == null) return;
    const [x1, y1] = this.project(sf.lat_a, sf.lon_a);
    const [x2, y2] = this.project(sf.lat_b, sf.lon_b);
    this.ctx.strokeStyle = "#ffffff";
    this.ctx.lineWidth = 2;
    this.ctx.setLineDash([6, 4]);
    this.ctx.beginPath();
    this.ctx.moveTo(x1, y1);
    this.ctx.lineTo(x2, y2);
    this.ctx.stroke();
    this.ctx.setLineDash([]);
  }

  bindPlacement() {
    const button = document.getElementById("set-start-finish");
    if (!button) return;
    button.addEventListener("click", () => {
      this.placing = [];
      button.textContent = "Click two points for the line…";
      this.canvas.style.cursor = "crosshair";
    });

    this.canvas.addEventListener("click", (e) => {
      if (this.placing.length >= 2 || this.canvas.style.cursor !== "crosshair") return;
      const rect = this.canvas.getBoundingClientRect();
      const x = (e.clientX - rect.left) * (this.canvas.width / rect.width);
      const y = (e.clientY - rect.top) * (this.canvas.height / rect.height);
      const [lat, lon] = this.unproject(x, y);
      this.placing.push({ lat, lon });
      if (this.placing.length === 2) this.submitLine();
    });
  }

  submitLine() {
    const [p1, p2] = this.placing;
    const form = document.createElement("form");
    form.method = "post";
    form.action = this.updateUrl;
    const fields = {
      _method: "patch",
      authenticity_token: document.querySelector('meta[name="csrf-token"]').content,
      "race[start_finish_lat_a]": p1.lat,
      "race[start_finish_lon_a]": p1.lon,
      "race[start_finish_lat_b]": p2.lat,
      "race[start_finish_lon_b]": p2.lon,
    };
    for (const [name, value] of Object.entries(fields)) {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      input.value = value;
      form.appendChild(input);
    }
    document.body.appendChild(form);
    form.submit();
  }
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll('[data-track-map="true"]').forEach((el) => new TrackMap(el));
});

export default TrackMap;
```

- [ ] **Step 2: Import it from the entrypoint**

Edit `app/packs/entrypoints/application.js`:
```js
import Rails from "@rails/ujs";
import "../scripts/track_map";

Rails.start();
```

- [ ] **Step 3: Run the feature spec**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb`
Expected: PASS — canvas present, page shows "Ready" and "No laps yet".

If the assets aren't compiled in the test env, run `bin/shakapacker` once (or ensure `compile: true` in `config/shakapacker.yml` for test). Capybara's headless Chrome loads the compiled pack.

- [ ] **Step 4: Commit**

```bash
git add app/packs/scripts/track_map.js app/packs/entrypoints/application.js
git commit -m "Add track map canvas rendering and start/finish placement"
```

---

## Task 12: Lap table interaction + manual verification

Highlight a lap's portion of the path when its row is clicked, and visually confirm the whole flow with the real sample CSV.

**Files:**
- Modify: `app/packs/scripts/track_map.js` (add lap highlight)
- Modify: `app/views/races/_lap_table.html.haml` (rows already carry `data-lap-id`)

- [ ] **Step 1: Add lap-highlight to the map module**

In `app/packs/scripts/track_map.js`, add inside the `TrackMap` constructor after `this.bindPlacement();`:
```js
    this.bindLapHighlight();
    this.highlightLap = null;
```

Add these methods to the class:
```js
  bindLapHighlight() {
    document.querySelectorAll(".lap-table tbody tr[data-lap-id]").forEach((row) => {
      row.style.cursor = "pointer";
      row.addEventListener("click", () => {
        const id = parseInt(row.dataset.lapId, 10);
        this.highlightLap = this.highlightLap === id ? null : id;
        document.querySelectorAll(".lap-table tbody tr").forEach((r) => r.classList.remove("table-active"));
        if (this.highlightLap) row.classList.add("table-active");
        this.draw();
      });
    });
  }
```

And in `draw()`, replace the segment `strokeStyle` line:
```js
      ctx.strokeStyle = speedColor(b.sp, min, max);
```
with:
```js
      const dimmed = this.highlightLap && b.lap !== this.highlightLap;
      ctx.strokeStyle = dimmed ? "rgba(120,120,120,0.25)" : speedColor(b.sp, min, max);
```

- [ ] **Step 2: Re-run the full suite**

Run: `bundle exec rake`
Expected: all specs PASS (models, services, jobs, requests, feature).

- [ ] **Step 3: Manual smoke test with the real sample data**

```bash
bin/dev                    # terminal 1
bin/shakapacker-dev-server # terminal 2
```
Visit `http://localhost:3000`, upload `public/short_example_telemetry_log.csv`, confirm the map draws. (That sample is a near-stationary log, so the line is tiny and laps won't form — expected. Use a moving-lap CSV to see laps.)

- [ ] **Step 4: Commit**

```bash
git add app/packs/scripts/track_map.js
git commit -m "Highlight selected lap on the track map"
```

---

## Self-review notes (coverage check)

- Upload → parse → samples: Tasks 1–2, 5, 8. ✓
- Speed-coloured abstract map: Task 11. ✓
- Click-to-set start/finish line: Tasks 8 (action), 11 (UI). ✓
- Auto lap detection + timing (segment crossing, interpolation, best lap): Tasks 6–7. ✓
- Lap table + click-to-highlight: Tasks 8, 12. ✓
- Warm-up `0,0` rows skipped on map + detection: Tasks 6 (detector filter), 11 (JS filter), `located` scope Task 2. ✓
- Fixed typed columns (migrations later): Tasks 1–3. ✓
- Future `user_id` accommodated (no auth now): Race has no hard coupling; additive later. ✓
- Background jobs via Delayed Job: `perform_later` used; specs run inline/test adapter. ✓

**Deferred (out of scope, per spec):** speed-trace + lap-compare chart, G-G diagram, Leaflet basemap, per-track saved lines, user accounts.
