# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Rails 8 application built from the **epiGenesys** (University of Sheffield Computer Science) group-project template. Most infrastructure (auth, CI, deployment, asset pipeline, error reporting) is pre-wired by the template.

The app displays **race-car telemetry** so a driver can see where to improve their laps. Telemetry arrives as **CSV files** (`public/short_example_telemetry_log.csv` is a sample); each uploaded file is one **race** (session). The app parses the rows into samples, draws the GPS racing line on a speed-coloured map, lets the user click a start/finish line, and **auto-detects + times laps** from where the path crosses it.

The telemetry dashboard described below is **implemented** (root route is `races#index`). The unused template `pages#home` controller/view still exist but are no longer wired to root.

- Ruby 3.4.5 (`.ruby-version`), Node 22 (`.node-version`), Yarn 1.x (Classic)
- PostgreSQL via Active Record
- Default Rails framework module is `Project` (see `config/application.rb`)

## Domain model (telemetry)

Design spec: `docs/superpowers/specs/2026-06-16-telemetry-dashboard-design.md`.

- **Race** — one uploaded CSV. Holds the original file (Active Storage), a `status` (pending/processing/ready/failed), the start/finish line coordinates (nullable until the user clicks them on the map), and cached counts. Built so a `user_id` can be added later (auth is off for now — single user).
- **TelemetrySample** — one CSV row: `offset_ms`, `sequence`, `lat`, `lon`, `speed`, `accel_x/y/z`, nullable `lap_id`. **Fixed typed columns** — new CSV columns get a migration each time (no dynamic/JSON store).
- **Lap** — belongs to a race; `number`, boundaries, `lap_time_ms`, cached `top_speed`; fastest = best.

Key units: `CsvTelemetryParser` (file → rows, no DB), `ParseRaceJob` (parse + bulk-insert samples), `LapDetector` (pure logic: samples + start/finish line → lap boundaries/times via segment-crossing), `DetectLapsJob` (persists laps). Map is drawn client-side on `<canvas>` in `app/packs/scripts/track_map.js` (aspect-correct abstract plot now — see projection note below; optional Leaflet basemap planned as a toggle). CSV warm-up rows (all-zero lat/lon/speed before GPS lock) are kept but skipped on the map and in lap detection.

Background jobs use Delayed Job (already configured — see below).

### Implementation notes (things that bite)

- **CSV format:** header is `timestamp,lat,lon,speed,accelX,accelY,accelZ`; `CsvTelemetryParser::COLUMN_MAP` maps those names to symbols and validates required headers (raises `InvalidFormat`). `timestamp` is milliseconds; `offset_ms` is stored relative to the **first** row. The parser skips blank/partial rows.
- **Pipeline trigger:** `RacesController#create` saves the race + attaches the CSV, then `ParseRaceJob.perform_later`. `RacesController#start_finish` (`PATCH /races/:id/start_finish`) saves the four `start_finish_*` coords, then `DetectLapsJob.perform_later`. Re-running either job is idempotent (parse upserts, detect deletes-then-rebuilds laps and re-tags samples).
- **`LapDetector`** treats `lon` as x and `lat` as y for sign tests, drops the out-/in-lap, ignores `0,0` points, and includes a GPS-jitter debounce so noise near the line doesn't double-count crossings. Crossing times are interpolated along the segment.
- **Front-end wiring:** `show.html.haml` serializes samples + start/finish coords into `data-*` attributes on a `[data-track-map]` element; `track_map.js` reads them, colours segments red→amber→green by speed, draws the line, supports click-to-place the start/finish line (submitted via a generated `<form>` with a hidden `_method=patch` and the CSRF token), and click-to-highlight a lap row.
- **Map projection (`TrackMap#computeBounds`/`project`/`unproject`):** lat/lon are projected onto a locally-planar metric that is **aspect-correct**. Longitude is scaled by `cos(midLat)` (meridians converge, so a degree of lon is a shorter ground distance than a degree of lat), and a **single uniform scale** (`Math.min` of the two axis fits) is used for both axes, letterboxing the track in the leftover space instead of stretching each axis independently to fill the canvas. `unproject` is the exact inverse (verified: round-trips to 0 error; a physically square track renders square). This is still an abstract plot, not georeferenced tiles — a Leaflet/Web-Mercator **basemap is planned as a toggle** (on = real map/satellite tiles under the line; off = this offline canvas, so it must keep working with no network).
- **Specs:** `spec/features/race_telemetry_spec.rb` is `js: true` (headless Chrome, compiles webpack on first run); the rest are fast model/service/job/request specs. Full suite is 32 examples.

## Commands

```bash
bin/setup                       # install deps, prepare DB, clear logs, start server (idempotent)
bin/dev                         # start the Rails server (alias for `bin/rails server`)
bin/shakapacker-dev-server      # run webpack dev server (recompiles JS/CSS on change) — run alongside bin/dev

bundle exec rake                # DEFAULT task = run the full RSpec suite (this is what CI runs)
bundle exec rspec               # run all specs
bundle exec rspec spec/path/to/file_spec.rb            # run one spec file
bundle exec rspec spec/path/to/file_spec.rb:42         # run a single example by line number

bundle exec brakeman            # static security scan (Rails)
bundle exec bundler-audit check --update               # gem vulnerability audit
yarn run improved-yarn-audit    # JS dependency audit
bundle exec annotaterb models   # refresh schema annotations on models/factories
```

Database lives under names `racing_telemetry_app_<env>` (`config/database.yml`). `bin/rails db:prepare` creates/migrates as needed.

### JS test debugging
Capybara feature specs use a **headless Chrome** Selenium driver (`spec/support/headless_chrome_config.rb`). Set `SHOW_CHROME=1` to watch the browser. CI talks to a remote Selenium service via `SELENIUM_HOST`/`SELENIUM_PORT`.

## Architecture & conventions

**Views: Hamlit (Haml), not ERB.** Generators are configured (`config/application.rb`) to emit `.haml` templates and to skip assets, helpers, jbuilder, and most spec types. Only model/system/request specs are generated by default — controller/view/routing/helper specs are off. Forms use `simple_form` styled for Bootstrap 5 (`config/initializers/simple_form_bootstrap.rb`).

**Assets via Shakapacker (webpack), not Sprockets.** Source lives in `app/packs/`:
- `app/packs/entrypoints/application.js` — JS entrypoint; import new scripts here
- `app/packs/entrypoints/styles.js` — imports SCSS from `app/packs/styles/`
- `app/packs/scripts/`, `app/packs/styles/`, `app/packs/images/`
Reference images in views with `image_pack_tag 'images/foo.png'`. See `GETTING_STARTED.md` for adding JS libs, CSS, and images. Bootstrap 5 (incl. its JS bundle, for dropdowns/collapse) + bootstrap-icons are bundled.

**JS interaction layer is `@rails/ujs` (Rails UJS), NOT Hotwire/Turbo** (no `@hotwired/turbo` is bundled; `application.js` calls `Rails.start()`). This matters for links that perform non-GET requests:
- Use `link_to "x", path, method: :delete, data: { confirm: "Sure?" }` → renders `data-method` / `data-confirm`, which UJS handles. Do **NOT** use `data: { turbo_method:, turbo_confirm: }` — those are Turbo attributes and are silently inert here (the link just does a GET, e.g. a "Delete" link that never deletes).
- `button_to ... method: :delete` works with zero JS (it's a real form) — preferred when you don't want a UJS dependency. CSRF meta tags are present, so UJS DELETE/POST requests are authenticated.

**Authentication = Devise; authorization = CanCanCan.** Multi-user accounts are live: a **username-only** `User` (no email — `config.authentication_keys = [:username]`, and `User#email_required?`/`email_changed?`/`will_save_change_to_email?` return false so `:validatable` ignores the missing email column). `devise_for :users` is declared; `ApplicationController` applies `authenticate_user!` globally; root is `dashboard#show`. Each `Race` `belongs_to :user`, and `RacesController` scopes every action through `current_user.races` (a non-owned record 404s). `app/models/ability.rb` holds `can :manage, Race, user_id: user.id` as defence-in-depth (the controller scoping is the primary gate; no action calls `authorize!` yet). `CanCan::AccessDenied` is mapped to a `403` response in `config/application.rb`. Login required everywhere means request/feature specs must authenticate: `sign_in user` (request specs — `Devise::Test::IntegrationHelpers`) or `login_as(user, scope: :user)` (feature specs — Warden).

**Presentation logic = Draper decorators** in `app/decorators/`.

**Background jobs = Delayed Job** (`config.active_job.queue_adapter = :delayed_job`). Jobs run via the `bin/delayed_job` daemon (managed by monit + Capistrano in production). Scheduled/cron tasks are defined with the `whenever` gem in `config/schedule.rb`.

**Error reporting = Sentry** (`sentry-rails`). The DSN in `config/initializers/sentry.rb` must be replaced per project (see `GETTING_STARTED.md`).

**Caching is disabled globally** by `ApplicationController#update_headers_to_disable_caching` (no-store headers on every response) to avoid caching sensitive data. Remove/relax this if the app is not sensitive and you want caching.

Models annotated with schema comments via `annotaterb` (config in `.annotaterb.yml`, position `before`).

## Environments & deployment

Five environments: `development`, `test`, plus **`qa`**, **`demo`**, `production` (`config/environments/`). Time zone is `London`.

Deployment is **Capistrano + epi_deploy** to Sheffield CompSci servers; per-stage config in `config/deploy/{qa,demo,production}.rb`. Deploy restarts the Delayed Job worker and refreshes monit + whenever crontab automatically. Project-specific deploy/Sentry/email setup steps are documented in `GETTING_STARTED.md` and must be filled in before deploying.

CI is **GitLab CI** (`.gitlab-ci.yml`), not GitHub Actions: stages are `setup` (bundler + yarn) → `test` (`bundle exec rake`) → `security` (bundler-audit, yarn-audit, brakeman). Security and test stages are skipped on `qa`/`demo`/`training` branches and tags.

## Testing stack

RSpec + Capybara + Selenium, FactoryBot (`spec/factories/`, `create`/`build` available unprefixed), DatabaseCleaner (transactions for normal specs, truncation for `js: true`), and SimpleCov (started in `spec/rails_helper.rb`). Helpers mixed in globally: `login_as` (Warden), Capybara DSL, route helpers, and Devise controller helpers. Test file fixtures resolve from `spec/factories/files`. Tag a spec `screenshot_on_failure: true` to auto-open a screenshot on failure, or `error_page: true` to exercise real production error pages.

## Git workflow

Do **not** run `git add`/`git commit` on this repo unless the user explicitly asks for it in that message — even if a task's written plan/instructions include a "commit" step. The user prefers to review the diff and commit manually. Finish the code/test changes and leave the working tree unstaged; report what changed and let the user stage/commit it themselves.
