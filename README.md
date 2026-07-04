# Racing Telemetry App

A Rails 8 app that turns race-car telemetry logs into an interactive dashboard so a
driver can see where to improve their laps. You upload a telemetry **CSV** (one file =
one race session); the app parses it into samples, draws the GPS racing line on a
speed-coloured map, lets you click a start/finish line, and **auto-detects and times
your laps** from where the path crosses that line.

## How it works

1. **Upload** a telemetry CSV on `/races/new`. Each upload becomes a `Race`.
2. A background job (`ParseRaceJob`) parses the rows into `TelemetrySample` records and
   records session stats (duration, sample count). Warm-up rows (all-zero lat/lon before
   the GPS locks) are kept but skipped on the map and in lap detection.
3. The race page renders the racing line on a `<canvas>`, coloured red→amber→green by
   speed, with the start/finish line drawn once it's set.
4. **Click two points** on the map to place the start/finish line. This triggers
   `DetectLapsJob`, which runs the pure-logic `LapDetector` (segment-crossing with
   time interpolation) to build timed `Lap` records.
5. The **lap table** lists each lap with its time and top speed, flags the fastest, and
   highlights a lap's portion of the path when you click its row.

### Domain model

- **Race** — one uploaded CSV. Has a `status` (pending/processing/ready/failed), the
  start/finish line coordinates (nullable until placed), cached counts, and the original
  file via Active Storage. Built so a `user_id` can be added later (single-user for now).
- **TelemetrySample** — one CSV row: `offset_ms`, `sequence`, `lat`, `lon`, `speed`,
  `accel_x/y/z`, nullable `lap_id`. Fixed typed columns — new CSV columns get a migration.
- **Lap** — belongs to a race; `number`, offset boundaries, `lap_time_ms`, cached
  `top_speed`, and a `best` flag for the fastest lap.

Key units: `CsvTelemetryParser` (file → row hashes, no DB), `LapDetector` (pure
segment-crossing math), and the `ParseRaceJob` / `DetectLapsJob` background jobs. The map
is plain JS on a `<canvas>` (`app/packs/scripts/track_map.js`).

## Requirements

- Ruby 3.4.5 (see `.ruby-version`)
- Node 22 (see `.node-version`) and Yarn 1.x (Classic)
- PostgreSQL

## Getting started

```bash
bin/setup    # install deps, prepare the DB, clear logs, and start the server (idempotent)
```

To run the app manually in two terminals:

```bash
bin/dev                       # Rails server
bin/shakapacker-dev-server    # webpack dev server (recompiles JS/CSS on change)
```

Then visit <http://localhost:3000> and upload a CSV. A sample log lives at
`public/short_example_telemetry_log.csv` — note it's a near-stationary recording, so the
line is tiny and no laps form; use a real moving-lap CSV to see lap detection.

Databases are named `racing_telemetry_app_<env>` (see `config/database.yml`).
`bin/rails db:prepare` creates/migrates as needed.

### CSV format

The parser expects this header (extra columns are ignored for now):

```csv
timestamp,lat,lon,speed,accelX,accelY,accelZ
```

`timestamp` is milliseconds; sample offsets are stored relative to the first row.

## Testing

```bash
bundle exec rake            # default task — runs the full RSpec suite (this is what CI runs)
bundle exec rspec           # all specs
bundle exec rspec spec/path/to/file_spec.rb       # one file
bundle exec rspec spec/path/to/file_spec.rb:42    # a single example by line
```

Feature specs (`spec/features/`) are `js: true` and drive a **headless Chrome** Selenium
browser, so they compile the webpack assets on first run. Set `SHOW_CHROME=1` to watch
the browser.

### Security scans

```bash
bundle exec brakeman                        # static security scan (Rails)
bundle exec bundler-audit check --update    # gem vulnerability audit
yarn run improved-yarn-audit                # JS dependency audit
```

## Tech stack

Rails 8 · PostgreSQL · Active Record · Active Storage (CSV files) · Delayed Job
(background jobs) · Hamlit (Haml views) · simple_form + Bootstrap 5 · Shakapacker
(webpack) · RSpec + Capybara + Selenium.

See `GETTING_STARTED.md` for template-specific setup (Sentry DSN, deploy targets, email),
and `CLAUDE.md` for architecture conventions and gotchas.

## Deployment

Capistrano + epi_deploy to Sheffield CompSci servers, across `qa`, `demo`, and
`production` stages (`config/deploy/`). CI is GitLab CI (`.gitlab-ci.yml`). Project-specific
deploy steps must be filled in per `GETTING_STARTED.md` before deploying.
