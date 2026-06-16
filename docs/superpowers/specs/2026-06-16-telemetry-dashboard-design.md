# Racing Telemetry Dashboard — Design

**Date:** 2026-06-16
**Status:** Approved (initial design)

## Purpose

A web app to display telemetry collected from a race car so the driver can see
where to improve their laps. Telemetry arrives as CSV files; each uploaded file
is one race (session). The app parses the data, draws the racing line on a
speed-coloured map, auto-detects laps, and times them.

## Users & scope

- **Now:** single user, no login. Anyone with access sees all races.
- **Later:** per-user accounts (Devise is already wired up in the template but
  switched off). The data model is built so a `user_id` can be added to `Race`
  as a clean, additive change.

## Example data

The current CSV (`public/short_example_telemetry_log.csv`) has columns:

```
timestamp,lat,lon,speed,accelX,accelY,accelZ
```

- `timestamp` — epoch milliseconds, ~10 Hz sampling (every ~100 ms)
- `lat`, `lon` — GPS position (~4 decimal places ≈ 10 m precision)
- `speed` — vehicle speed
- `accelX/Y/Z` — accelerometer in g (Z ≈ 0.98 at rest = gravity)

The leading rows have all-zero lat/lon/speed (GPS not yet locked — "warm-up"
rows). Future CSVs will add more columns.

## Core flow

1. **Upload** a CSV → app stores the original file (Active Storage) and enqueues
   background parsing. Race created with `status: pending`.
2. **Parse** every row into `TelemetrySample` records; compute race start time,
   duration, sample count; set `status: ready`. The GPS path renders on the hero
   map immediately — no laps required yet.
3. **Set start/finish** — the user clicks two points on the map to define the
   start/finish line. Coordinates saved on the `Race`.
4. **Detect laps** — a background job runs `LapDetector`, which finds where the
   path crosses the line, builds `Lap` records, assigns samples to laps, and
   times each lap. Fastest lap flagged as best.
5. **Explore** — race page shows the hero map (speed-coloured racing line) with
   the lap table beneath it. Clicking a lap highlights its segment on the map.

Two clean phases: map appears after upload; laps appear after the line is drawn.

## Data model

### Race
- `name` (string, defaults from filename)
- `recorded_at` / `duration_ms`
- `status` enum: `pending` / `processing` / `ready` / `failed`
- `start_finish_lat_a`, `start_finish_lon_a`, `start_finish_lat_b`,
  `start_finish_lon_b` — the start/finish line segment (nullable until set)
- cached counts: `sample_count`, `lap_count`
- `has_one_attached :csv_file` (original upload)
- **Future:** `user_id` (not added now; design accommodates it)
- `has_many :telemetry_samples`, `has_many :laps`

### TelemetrySample
- `race_id` (FK, indexed)
- `lap_id` (FK, nullable — assigned during lap detection)
- `offset_ms` (integer — milliseconds from race start)
- `sequence` (integer — order within race)
- `lat`, `lon`, `speed`, `accel_x`, `accel_y`, `accel_z` (floats)
- **Fixed typed columns** per decision — new CSV columns get a migration each
  time, not a dynamic/JSON store.

### Lap
- `race_id` (FK), `number` (1-based)
- lap boundaries (start/end sample or offsets)
- `lap_time_ms`
- cached `top_speed`
- best lap = fastest; flagged or computed.

Associations: `Race has_many :laps, :telemetry_samples`;
`Lap belongs_to :race, has_many :telemetry_samples`;
`TelemetrySample belongs_to :race, belongs_to :lap (optional)`.

## Components (small, isolated, testable)

- **`CsvTelemetryParser`** — validates headers, turns a CSV file/IO into parsed
  rows. No DB knowledge.
- **`ParseRaceJob`** (Delayed Job) — runs the parser, bulk-inserts samples
  (`insert_all`), fills in race stats, sets status.
- **`LapDetector`** — **pure logic**: ordered samples + start/finish line
  segment → lap boundaries and times. Uses line-segment intersection between
  consecutive samples and the start/finish segment; interpolates the exact
  crossing moment for accurate lap times. Unit-testable with synthetic data.
- **`DetectLapsJob`** — persists `LapDetector` output as `Lap` records and tags
  samples with `lap_id`.
- **Front-end map module** (`app/packs/scripts/`) — draws the path on a
  `<canvas>`, projects lat/lon to screen (simple equirectangular projection over
  the small area), colours segments by speed (red→amber→green normalised to the
  race's speed range), and handles click-to-set-line. Abstract plot now; a
  Leaflet basemap can be slotted in later.
- **Controllers** — `RacesController` (index, new, create, show, destroy) plus a
  member action to set the start/finish line (which enqueues `DetectLapsJob`).

## Map rendering

Abstract plot (no basemap) for now. Project lat/lon to x/y with an
equirectangular approximation (`x = lon·cos(lat₀)`, `y = lat`), scale to fit the
viewport. Each path segment coloured by speed. `0,0` warm-up points are skipped.
Designed so a real Leaflet tile basemap can be added later.

## Edge cases & risks

- **Warm-up rows:** all-zero lat/lon/speed rows are kept as samples but excluded
  from the map projection and lap detection.
- **GPS precision:** ~10 m coordinate resolution is coarse for line-crossing, so
  the start/finish line uses a tolerance band. Finer future data only improves
  results.
- **Partial laps:** the out-lap (before first crossing) and in-lap (after last
  crossing) are not complete laps — handled explicitly by `LapDetector`.
- **No crossings:** if the path never crosses the line, no laps are produced and
  the UI says so.

## Testing

- **`LapDetector`** (most coverage): synthetic paths crossing a known line;
  edge cases — no crossing, single lap, partial out/in laps, exact-vertex
  crossings.
- **`CsvTelemetryParser`**: parses the real sample CSV including warm-up rows;
  rejects malformed/missing headers.
- **Request specs**: upload flow, race show page, set-start/finish endpoint.
- **Feature spec** (Capybara, headless Chrome): full journey — upload CSV → see
  map → set line → see laps.

## Out of scope (for now)

- User accounts / auth (designed for, not built).
- Speed-trace + lap-comparison chart and G-G / friction-circle view (valuable
  later additions; core is map + lap table).
- Leaflet basemap, per-track saved start/finish lines.
