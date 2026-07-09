# Track Scrubber with Car Dot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a timeline scrubber and a play/pause control under the Leaflet track map that drive a car dot along the racing line, spanning the selected lap or the whole session.

**Architecture:** A new self-contained `TrackScrubber` class (`app/packs/scripts/track_scrubber.js`) owns all timeline state (current time, playing/paused), the slider + play button + readout DOM, the `L.circleMarker` car dot, the `requestAnimationFrame` playback loop, and time→position interpolation. `LeafletTrackMap` gains a thin seam: it instantiates the scrubber and calls a selection-changed hook from its existing `setSelectedLap` path — the map class knows nothing about time. The control-strip markup lives in `show.html.haml`. **No server-side change of any kind** (no controller, model, route, job, or serialized-data change).

**Tech Stack:** ES6 (Shakapacker/webpack, Babel), Leaflet 1.x, Bootstrap 5 + bootstrap-icons, Hamlit (Haml) views, RSpec + Capybara feature specs (`js: true`, headless Chrome).

---

## Repo conventions that constrain this plan

- **DO NOT run `git add` / `git commit`.** Per `CLAUDE.md`, the user reviews the diff and commits manually. Every task therefore ends by leaving the working tree unstaged — there are **no commit steps** in this plan. Where the writing-plans template would commit, we instead confirm the tree is clean-of-staging and stop.
- **Views are Haml, not ERB.** Indentation is significant.
- **JS is bundled via Shakapacker.** `track_scrubber.js` is imported by `leaflet_track_map.js`, so `application.js` needs **no** change.
- **Feature specs are slow** (`js: true` compiles webpack on first run). Run individual scenarios with `-e "<name>"` while iterating.

## File Structure

- **Create: `app/packs/scripts/track_scrubber.js`** — the `TrackScrubber` class. One responsibility: timeline → dot + readout + slider, and playback.
- **Modify: `app/packs/scripts/leaflet_track_map.js`** — import + instantiate the scrubber; expose `map`/`samples`/`selectedLap` (already public fields); call `this.scrubber.handleSelectionChange()` from `setSelectedLap`.
- **Modify: `app/views/races/show.html.haml`** — control-strip markup (play button, range input, readout) between the map div and the caption row, hidden by default (`d-none`) so it only appears once the scrubber mounts.
- **Modify: `app/packs/styles/track_map.scss`** — one small rule so the range flexes correctly.
- **Modify: `spec/features/race_telemetry_spec.rb`** — five new `js: true` scenarios.

### Data facts the code relies on (verified against the repo)

- Each serialized sample is `{ t, lat, lon, sp, lap }` where `t` = `offset_ms` (relative to the first row) and `lap` = `lap_id` (or `null`). Source: `RacesController#show` (`app/controllers/races_controller.rb:26-32`).
- `LeafletTrackMap` already filters warm-up `(0,0)` rows and stores the result on `this.samples`; it early-returns (never mounting, so the scrubber is never built) when `this.samples.length < 2` (`leaflet_track_map.js:23-31`). `this.map` is set in `initMap` before the scrubber is constructed. `this.selectedLap` and `this.root` are public.
- Samples are serialized in `sequence` order, which is time order, so `this.samples` is already sorted ascending by `t`.
- The server formats lap times as `M:SS.mmm` via `format("%d:%06.3f", minutes, seconds)` (`app/models/lap.rb:31-36`). The scrubber must reproduce this exactly.

---

## Task 1: Control strip + scrubber scaffold (renders readout, dot, and mounts)

Builds the markup and a `TrackScrubber` that reveals the strip, computes the **session** time domain, renders the `current / total` readout, mirrors current time to `#track-map[data-scrub-ms]`, and places the car dot. No slider interaction and no playback yet (added in Tasks 2 and 4). Lap-specific domains are added in Task 3 — for now the domain is always the whole session.

**Files:**
- Create: `app/packs/scripts/track_scrubber.js`
- Modify: `app/packs/scripts/leaflet_track_map.js:5` (import), `:31-40` (constructor tail), `:208-220` (`setSelectedLap`)
- Modify: `app/views/races/show.html.haml:22-27`
- Modify: `app/packs/styles/track_map.scss`
- Test: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/features/race_telemetry_spec.rb`, inside the `RSpec.feature "Race telemetry", js: true do` block (after the last scenario, before the final `end`):

```ruby
  scenario "renders the scrubber controls with a position/time readout" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 90_000, lat: 53.001, lon: -1.001, speed: 20)

    visit race_path(race)

    expect(page).to have_css("#scrub-play")
    expect(page).to have_css("#scrub-range")
    expect(page).to have_css("#scrub-readout", text: "0:00.000 / 1:30.000")
    expect(page).to have_css("#track-map[data-scrub-ms='0']")
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "renders the scrubber controls"`
Expected: FAIL — `#scrub-play` / `#scrub-readout` not found (markup and scrubber don't exist yet).

- [ ] **Step 3: Add the control-strip markup to the view**

In `app/views/races/show.html.haml`, replace the map/caption block (lines 22-27):

```haml
          .track-map-leaflet.w-100
          .d-flex.align-items-center.justify-content-between.mt-3
            %span#lap-caption.fw-semibold.text-body-secondary
            %div
              %button#toggle-basemap.btn.btn-outline-secondary.me-2{ type: "button", "aria-pressed": "false" } Satellite
              %button#set-start-finish.btn.btn-outline-primary{ type: "button" } Set start/finish line
```

with (adds the `#scrubber` strip between the map and the caption row):

```haml
          .track-map-leaflet.w-100
          #scrubber.d-none.d-flex.align-items-center.gap-2.mt-3
            %button#scrub-play.btn.btn-outline-secondary.btn-sm{ type: "button", "aria-pressed": "false", "aria-label": "Play" }
              %i.bi.bi-play-fill
            %input#scrub-range.form-range.flex-grow-1{ type: "range", min: "0", value: "0", step: "1" }
            %span#scrub-readout.text-body-secondary.font-monospace 0:00.000 / 0:00.000
          .d-flex.align-items-center.justify-content-between.mt-3
            %span#lap-caption.fw-semibold.text-body-secondary
            %div
              %button#toggle-basemap.btn.btn-outline-secondary.me-2{ type: "button", "aria-pressed": "false" } Satellite
              %button#set-start-finish.btn.btn-outline-primary{ type: "button" } Set start/finish line
```

- [ ] **Step 4: Create the scrubber scaffold**

Create `app/packs/scripts/track_scrubber.js`:

```js
// Timeline scrubber + car dot for the Leaflet track map. Owns the current
// "playback time" as the single source of truth: the slider drives it, and
// (from Task 4) a requestAnimationFrame loop drives it during play. The map
// class knows nothing about time — it just hands us map/samples/selectedLap
// and calls handleSelectionChange() when the isolated lap changes.
import L from "leaflet";

// White ring + dark fill circle in the marker pane, which stacks above the
// overlay pane holding the racing-line canvas, so the dot is always on top.
const DOT_OPTIONS = {
  radius: 8,
  color: "#ffffff",
  weight: 2,
  fillColor: "#111111",
  fillOpacity: 1,
  interactive: false,
  pane: "markerPane",
};

// Reproduce the server's Lap#formatted_time ("%d:%06.3f") in JS: M:SS.mmm.
function formatTime(ms) {
  const totalSeconds = ms / 1000;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds - minutes * 60;
  return `${minutes}:${seconds.toFixed(3).padStart(6, "0")}`;
}

class TrackScrubber {
  constructor(trackMap) {
    this.trackMap = trackMap;
    this.map = trackMap.map;
    this.root = trackMap.root;
    this.samples = trackMap.samples; // already filtered + time-ordered

    this.strip = document.getElementById("scrubber");
    this.playButton = document.getElementById("scrub-play");
    this.range = document.getElementById("scrub-range");
    this.readout = document.getElementById("scrub-readout");
    if (!this.strip || !this.range || this.samples.length < 2) return;

    this.playing = false;
    this.rafId = null;
    this.relMs = 0; // current time, RELATIVE to the domain start (0..span)

    this.dot = L.circleMarker(
      [this.samples[0].lat, this.samples[0].lon],
      DOT_OPTIONS
    ).addTo(this.map);

    this.setDomain();
    this.setTime(0);
    this.strip.classList.remove("d-none");
  }

  // The samples that make up the current time domain. Task 3 adds lap
  // filtering here; for now the domain is always the whole session.
  domainSamplesFor() {
    return this.samples;
  }

  setDomain() {
    this.domainSamples = this.domainSamplesFor();
    this.domainStart = this.domainSamples[0].t;
    this.domainEnd = this.domainSamples[this.domainSamples.length - 1].t;
    this.span = this.domainEnd - this.domainStart;
    this.range.min = "0";
    this.range.max = String(this.span);
  }

  // Set the current (domain-relative) time and reflect it everywhere.
  setTime(relMs) {
    this.relMs = Math.max(0, Math.min(this.span, relMs));
    this.range.value = String(this.relMs);
    this.root.dataset.scrubMs = String(Math.round(this.relMs));
    this.readout.textContent = `${formatTime(this.relMs)} / ${formatTime(this.span)}`;
    const [lat, lon] = this.positionAt(this.domainStart + this.relMs);
    this.dot.setLatLng([lat, lon]);
  }

  // Linear interpolation of lat/lon at an ABSOLUTE offset time, between the
  // bracketing sample pair. Glides across GPS gaps with no special handling.
  positionAt(absMs) {
    const s = this.domainSamples;
    if (absMs <= s[0].t) return [s[0].lat, s[0].lon];
    const last = s[s.length - 1];
    if (absMs >= last.t) return [last.lat, last.lon];
    for (let i = 1; i < s.length; i++) {
      if (s[i].t >= absMs) {
        const a = s[i - 1];
        const b = s[i];
        const span = b.t - a.t || 1;
        const f = (absMs - a.t) / span;
        return [a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f];
      }
    }
    return [last.lat, last.lon];
  }

  pause() {
    this.playing = false;
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }

  // Called by LeafletTrackMap whenever the isolated lap changes (including the
  // best-lap auto-select on load). Any domain change pauses and resets to the
  // domain start — carrying a mid-lap time across laps is silently wrong.
  handleSelectionChange() {
    this.pause();
    this.setDomain();
    this.setTime(0);
  }
}

export default TrackScrubber;
```

- [ ] **Step 5: Wire the scrubber into `LeafletTrackMap`**

In `app/packs/scripts/leaflet_track_map.js`, add the import after the Leaflet import (line 5):

```js
import L from "leaflet";
import TrackScrubber from "./track_scrubber";
```

Instantiate the scrubber in the constructor. Replace the constructor tail (currently lines 33-40):

```js
    this.initMap();
    this.buildSegments();
    this.buildStartFinish();
    this.bindBasemapToggle();
    this.bindPlacement();
    this.bindLapSelection();
    this.selectDefaultLap();
```

with (the scrubber must exist **before** `selectDefaultLap`, whose `setSelectedLap` call notifies it):

```js
    this.initMap();
    this.buildSegments();
    this.buildStartFinish();
    this.bindBasemapToggle();
    this.bindPlacement();
    this.bindLapSelection();
    this.scrubber = new TrackScrubber(this);
    this.selectDefaultLap();
```

Notify the scrubber from `setSelectedLap`. Replace its tail (currently lines 217-220):

```js
    this.updateCaption();
    // switching laps keeps the user's pan/zoom to help comparison
    this.redraw();
  }
```

with:

```js
    this.updateCaption();
    // switching laps keeps the user's pan/zoom to help comparison
    this.redraw();
    if (this.scrubber) this.scrubber.handleSelectionChange();
  }
```

- [ ] **Step 6: Add the SCSS width rule**

Append to `app/packs/styles/track_map.scss`:

```scss
// Let the range input actually shrink/grow inside the flex control strip.
#scrub-range {
  min-width: 0;
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "renders the scrubber controls"`
Expected: PASS.

- [ ] **Step 8: Leave the tree unstaged (no commit)**

Run: `git status`
Expected: `track_scrubber.js` shown as untracked; `leaflet_track_map.js`, `show.html.haml`, `track_map.scss`, and the spec shown as modified — **all unstaged**. Do not `git add` or `git commit`. Report the changes and stop.

---

## Task 2: Slider scrubs the timeline (updates readout, dot, and `data-scrub-ms`)

Wire the range input's `input` event (live while dragging, per the spec) to `setTime`, so moving the slider moves the dot and updates the readout and `#track-map[data-scrub-ms]`.

**Files:**
- Modify: `app/packs/scripts/track_scrubber.js`
- Test: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/features/race_telemetry_spec.rb`:

```ruby
  scenario "scrubbing the slider updates the readout and data-scrub-ms" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 90_000, lat: 53.001, lon: -1.001, speed: 20)

    visit race_path(race)

    # End jumps a native range to its max (the full domain span).
    find("#scrub-range").send_keys(:end)

    expect(page).to have_css("#track-map[data-scrub-ms='90000']")
    expect(page).to have_css("#scrub-readout", text: "1:30.000 / 1:30.000")
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "scrubbing the slider"`
Expected: FAIL — `data-scrub-ms` stays `"0"` because nothing listens to the range input yet.

- [ ] **Step 3: Bind the range input**

In `app/packs/scripts/track_scrubber.js`, add a `bindControls` call at the end of the constructor. Change:

```js
    this.setDomain();
    this.setTime(0);
    this.strip.classList.remove("d-none");
  }
```

to:

```js
    this.setDomain();
    this.setTime(0);
    this.bindControls();
    this.strip.classList.remove("d-none");
  }
```

Then add the `bindControls` method (place it directly after the constructor, before `domainSamplesFor`):

```js
  bindControls() {
    // "input" (not just "change") fires continuously while dragging, so the
    // dot tracks the thumb live. Task 4 adds play/pause here too.
    this.range.addEventListener("input", () => {
      this.setTime(Number(this.range.value));
    });
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "scrubbing the slider"`
Expected: PASS.

- [ ] **Step 5: Leave the tree unstaged (no commit)**

Run: `git status`
Expected: `track_scrubber.js` and the spec modified, unstaged. Do not commit.

---

## Task 3: Lap-scoped time domain (selected lap vs. whole session)

When a lap is isolated, the domain becomes that lap's `[min t, max t]` derived from its samples; deselecting returns to the session domain. Because `handleSelectionChange` already pauses + resets to the domain start (Task 1), this task only adds the lap filter.

**Files:**
- Modify: `app/packs/scripts/track_scrubber.js`
- Test: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/features/race_telemetry_spec.rb`. The lap covers the first two samples (0–90 s); a third untagged sample extends the session to 120 s:

```ruby
  scenario "the time domain follows the selected lap and resets on deselect" do
    race = create(:race, user: user, status: :ready, sample_count: 3)
    lap = create(:lap, race: race, number: 1, best: true, lap_time_ms: 90_000)
    create(:telemetry_sample, race: race, lap: lap, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, lap: lap, sequence: 1, offset_ms: 90_000, lat: 53.001, lon: -1.001, speed: 20)
    create(:telemetry_sample, race: race, sequence: 2, offset_ms: 120_000, lat: 53.002, lon: -1.002, speed: 5)

    visit race_path(race)

    # Best lap auto-selected on load: domain total is the lap's span.
    expect(page).to have_css("#scrub-readout", text: "0:00.000 / 1:30.000")

    # Deselect (click the active lap row): domain becomes the whole session.
    find("tr[data-lap-id='#{lap.id}']").click
    expect(page).to have_css("#scrub-readout", text: "0:00.000 / 2:00.000")
    expect(page).to have_css("#track-map[data-scrub-ms='0']")
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "the time domain follows the selected lap"`
Expected: FAIL — the auto-selected-lap readout shows `2:00.000` (session span), not `1:30.000`, because `domainSamplesFor` ignores the lap.

- [ ] **Step 3: Add the lap filter**

In `app/packs/scripts/track_scrubber.js`, replace `domainSamplesFor`:

```js
  // The samples that make up the current time domain. Task 3 adds lap
  // filtering here; for now the domain is always the whole session.
  domainSamplesFor() {
    return this.samples;
  }
```

with:

```js
  // The samples that make up the current time domain: the isolated lap's
  // samples when one is selected, otherwise the whole session. Falls back to
  // the session if a lap somehow has fewer than 2 samples.
  domainSamplesFor() {
    const lap = this.trackMap.selectedLap;
    if (lap === null) return this.samples;
    const inLap = this.samples.filter((s) => s.lap === lap);
    return inLap.length >= 2 ? inLap : this.samples;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "the time domain follows the selected lap"`
Expected: PASS.

- [ ] **Step 5: Leave the tree unstaged (no commit)**

Run: `git status`
Expected: `track_scrubber.js` and the spec modified, unstaged. Do not commit.

---

## Task 4: Play / pause (real-time playback via requestAnimationFrame)

The play button advances the current time in real elapsed time (1×) through the same `setTime` path as the slider. Reaching the domain end pauses (no loop). Dragging the slider while playing pauses playback. The button's `aria-pressed` and bootstrap-icons glyph flip with state.

**Files:**
- Modify: `app/packs/scripts/track_scrubber.js`
- Test: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/features/race_telemetry_spec.rb`. The 90 s span means playback won't reach the end during the test window:

```ruby
  scenario "play advances the dot in real time and pause freezes it" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 90_000, lat: 53.001, lon: -1.001, speed: 20)

    visit race_path(race)

    find("#scrub-play").click
    expect(page).to have_css("#scrub-play[aria-pressed='true']")
    # Advanced past the start within the Capybara wait window.
    expect(page).to have_no_css("#track-map[data-scrub-ms='0']")

    find("#scrub-play").click
    expect(page).to have_css("#scrub-play[aria-pressed='false']")

    frozen = find("#track-map")["data-scrub-ms"]
    sleep 0.4
    expect(find("#track-map")["data-scrub-ms"]).to eq(frozen)
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "play advances the dot"`
Expected: FAIL — clicking `#scrub-play` does nothing (no handler bound), so `aria-pressed` stays `"false"`.

- [ ] **Step 3: Bind the play button**

In `app/packs/scripts/track_scrubber.js`, extend `bindControls`. Replace:

```js
  bindControls() {
    // "input" (not just "change") fires continuously while dragging, so the
    // dot tracks the thumb live. Task 4 adds play/pause here too.
    this.range.addEventListener("input", () => {
      this.setTime(Number(this.range.value));
    });
  }
```

with:

```js
  bindControls() {
    this.playButton.addEventListener("click", () => this.togglePlay());
    // "input" (not just "change") fires continuously while dragging, so the
    // dot tracks the thumb live. Dragging while playing pauses playback.
    this.range.addEventListener("input", () => {
      if (this.playing) this.pause();
      this.setTime(Number(this.range.value));
    });
  }
```

- [ ] **Step 4: Add the playback methods and reflect button state in `pause`**

Bind the rAF callback in the constructor so `this` is correct. Change the constructor tail:

```js
    this.setDomain();
    this.setTime(0);
    this.bindControls();
    this.strip.classList.remove("d-none");
  }
```

to:

```js
    this.tick = this.tick.bind(this);
    this.setDomain();
    this.setTime(0);
    this.bindControls();
    this.updatePlayButton();
    this.strip.classList.remove("d-none");
  }
```

Update `pause` to also refresh the button. Replace:

```js
  pause() {
    this.playing = false;
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }
```

with:

```js
  play() {
    if (this.span <= 0) return;
    // Reaching the end pauses at the end; play again restarts from the start.
    if (this.relMs >= this.span) this.setTime(0);
    this.playing = true;
    this.updatePlayButton();
    this.lastFrame = performance.now();
    this.rafId = requestAnimationFrame(this.tick);
  }

  pause() {
    this.playing = false;
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
    this.updatePlayButton();
  }

  togglePlay() {
    if (this.playing) this.pause();
    else this.play();
  }

  // Advance current time by real elapsed wall-clock time (1x playback).
  tick(now) {
    if (!this.playing) return;
    const delta = now - this.lastFrame;
    this.lastFrame = now;
    const next = this.relMs + delta;
    if (next >= this.span) {
      this.setTime(this.span);
      this.pause(); // reach the end -> pause, no loop
      return;
    }
    this.setTime(next);
    this.rafId = requestAnimationFrame(this.tick);
  }

  updatePlayButton() {
    this.playButton.setAttribute("aria-pressed", String(this.playing));
    this.playButton.setAttribute("aria-label", this.playing ? "Pause" : "Play");
    const icon = this.playButton.querySelector("i");
    if (icon) icon.className = this.playing ? "bi bi-pause-fill" : "bi bi-play-fill";
  }
```

Note: `pause()` now calls `updatePlayButton()`, which is also called in the constructor after `this.playButton` is confirmed present — safe. `handleSelectionChange` (Task 1) already calls `pause()`, so a domain change also resets the button to "Play".

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "play advances the dot"`
Expected: PASS.

- [ ] **Step 6: Leave the tree unstaged (no commit)**

Run: `git status`
Expected: `track_scrubber.js` and the spec modified, unstaged. Do not commit.

---

## Task 5: No-mount guard (fewer than 2 usable samples → no controls)

When the map never mounts (`< 2` usable samples), `LeafletTrackMap` early-returns before constructing the scrubber, so `#scrubber` keeps its default `d-none` class and none of the controls are visible. This task locks that behaviour with a test — no new production code is expected.

**Files:**
- Test: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Write the test**

Add to `spec/features/race_telemetry_spec.rb`. Capybara's default visibility filter means a `d-none` element is treated as absent, so `have_no_css` passes when the strip stays hidden:

```ruby
  scenario "does not show scrubber controls when the map cannot mount" do
    race = create(:race, user: user, status: :ready, sample_count: 1)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)

    visit race_path(race)

    expect(page).to have_content("Ready")
    expect(page).to have_no_css("#scrub-play")
    expect(page).to have_no_css("#scrub-range")
  end
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb -e "does not show scrubber controls"`
Expected: PASS (the strip renders in the DOM but stays `d-none`, so it is not visible).

If it FAILS, the guard is wrong: confirm `#scrubber` still carries `d-none` in `show.html.haml` and that the scrubber is only constructed inside `LeafletTrackMap` (which early-returns at `samples.length < 2`). Fix, then re-run.

- [ ] **Step 3: Run the full feature suite**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb`
Expected: all scenarios PASS (the 7 original + 5 new).

- [ ] **Step 4: Run the whole suite**

Run: `bundle exec rake`
Expected: green. (This is what CI runs.)

- [ ] **Step 5: Leave the tree unstaged (no commit)**

Run: `git status`
Expected: only the spec modified since Task 4, unstaged. Do not commit. Report the full set of changes for the user to review and commit manually.

---

## Self-Review (checked against the spec)

**Spec coverage:**
- Timeline scrubber under the map, drag → dot moves — Task 1 (dot) + Task 2 (slider). ✅
- Play/pause at 1× via rAF, pause freezes — Task 4. ✅
- Domain spans selected lap or whole session — Task 3. ✅
- Position + time readout `M:SS.mmm` matching the server format — Task 1 (`formatTime`). ✅
- Simple `L.circleMarker` dot in the marker pane, above the line canvas — Task 1 (`DOT_OPTIONS.pane = "markerPane"`). ✅
- Interpolated motion between bracketing samples — Task 1 (`positionAt`). ✅
- Domain change pauses + resets to domain start (incl. best-lap auto-select on load) — Task 1 (`handleSelectionChange`) + Task 4 (button reset via `pause`). ✅
- Reaching domain end pauses, no loop; play again restarts from start — Task 4 (`tick` + `play`). ✅
- Dragging while playing pauses — Task 4 (`bindControls`). ✅
- `#track-map[data-scrub-ms]`, domain-relative, `"0"` at domain start — Task 1 (`setTime`). ✅
- Native range = free keyboard support (arrows/Home/End) — Task 1 markup; exercised in Task 2 test. ✅
- No-mount guard (<2 usable samples → no controls) — Task 5. ✅
- Control strip in the existing card, above the caption row, Bootstrap flex — Task 1 view + SCSS. ✅
- No auto-follow camera / no server change / no speed multipliers — nothing in the plan adds them. ✅ (out of scope, correctly absent)
- All five spec-listed feature tests present — Tasks 1–5. ✅

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to Task N"; every code step shows complete code. ✅

**Type/name consistency:** `TrackScrubber`, `handleSelectionChange`, `setDomain`, `domainSamplesFor`, `setTime`, `positionAt`, `pause`, `play`, `togglePlay`, `tick`, `updatePlayButton`, `bindControls`, and fields `relMs`/`span`/`domainSamples`/`domainStart`/`domainEnd`/`rafId`/`lastFrame` are used identically across tasks. DOM ids `#scrubber`/`#scrub-play`/`#scrub-range`/`#scrub-readout` and attribute `data-scrub-ms` match between the view, the JS, and the specs. ✅
