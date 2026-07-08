# Lap Isolation on the Track Map — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Selecting a lap renders only that lap on the track-map canvas (instead of dimming the others), with the fastest lap auto-selected on load and a caption naming what's shown.

**Architecture:** Pure front-end change. `TrackMap` gains a `selectedLap` filter (a lap id or `null` for full session). `draw()` skips segments not belonging to `selectedLap`. Selection is driven by clicking lap rows; the best lap (`tr.table-success`) is selected on load. A caption element mirrors the current selection. No model, controller, route, job, or serialized-data changes — samples already carry their `lap` id and the best row is already marked.

**Tech Stack:** Vanilla JS (`app/packs/scripts/track_map.js`, ES class, no framework), Hamlit view, RSpec + Capybara `js: true` feature spec (headless Chrome).

**Spec:** `docs/superpowers/specs/2026-07-04-lap-isolation-track-map-design.md`

---

## Background the engineer needs

- **How samples reach the canvas:** `RacesController#show` builds `@samples_json` as an array of `{ t:, lat:, lon:, sp:, lap: }` where `lap` is the row's `lap_id` (nullable — warm-up, out-lap and in-lap samples have `lap: null`). It is serialized into `#track-map[data-samples]` in `app/views/races/show.html.haml`. In JS each sample object is `s`, so the lap id is `s.lap`.
- **The lap table:** rendered by `app/views/races/_lap_table.html.haml` as `table.lap-table`. Each `tbody tr` has `data-lap-id="<Lap#id>"`, and the best lap's row also has the Bootstrap class `table-success`. The three `td`s are, in order: lap **number**, formatted **time**, **top speed**.
- **`table-active`** is the Bootstrap "selected row" class currently applied on highlight; we keep using it to mark the selected lap.
- **Current behaviour being replaced:** `bindLapHighlight()` sets `this.highlightLap` and `draw()` dims non-matching segments to grey. Both are removed.
- **Testing note:** feature specs are `js: true` and compile webpack on first run (slow first invocation). They assert **DOM-observable** state — canvas pixels are not assertable — so we verify via `table-active`, the caption text, and a `data-selected-lap` attribute on the map root.
- **Factory defaults:** `create(:lap, ...)` has `best: false` by default (`spec/factories/laps.rb`). Tests that need an auto-selected lap must pass `best: true`.

## File structure

- **Modify:** `app/packs/scripts/track_map.js` — replace the highlight logic with `selectedLap` selection + render filter + caption. This is the whole behaviour; the file stays small and single-purpose (draw a track, place the line, isolate a lap).
- **Modify:** `app/views/races/show.html.haml` — add the `#lap-caption` element next to the canvas.
- **Modify (tests):** `spec/features/race_telemetry_spec.rb` — add scenarios for default selection, isolate-on-click, and deselect.

---

## Task 1: Implement lap isolation (view + JS + specs)

**Files:**
- Modify: `app/views/races/show.html.haml:22-23`
- Modify: `app/packs/scripts/track_map.js` (whole file)
- Test: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Write the failing feature specs**

Add these two scenarios to `spec/features/race_telemetry_spec.rb`, inside the existing `RSpec.feature "Race telemetry", js: true do ... end` block (after the existing `"clicking a lap row highlights it"` scenario):

```ruby
  scenario "auto-selects the fastest lap on load" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.001, lon: -1.001, speed: 20)
    slow = create(:lap, race: race, number: 1, best: false)
    fast = create(:lap, race: race, number: 2, best: true, lap_time_ms: 80_000)

    visit race_path(race)

    expect(page).to have_css("tr[data-lap-id='#{fast.id}'].table-active")
    expect(page).to have_no_css("tr[data-lap-id='#{slow.id}'].table-active")
    expect(page).to have_css("#lap-caption", text: "Lap 2")
    expect(page).to have_css("#track-map[data-selected-lap='#{fast.id}']")
  end

  scenario "clicking a lap isolates it and re-clicking returns to all laps" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.001, lon: -1.001, speed: 20)
    lap1 = create(:lap, race: race, number: 1, best: true)
    lap2 = create(:lap, race: race, number: 2, best: false)

    visit race_path(race)
    expect(page).to have_css("#lap-caption", text: "Lap 1")

    find("tr[data-lap-id='#{lap2.id}']").click
    expect(page).to have_css("tr[data-lap-id='#{lap2.id}'].table-active")
    expect(page).to have_css("#lap-caption", text: "Lap 2")

    find("tr[data-lap-id='#{lap2.id}']").click
    expect(page).to have_no_css("tr.table-active")
    expect(page).to have_css("#lap-caption", text: "All laps")
  end
```

- [ ] **Step 2: Run the new specs to verify they fail**

Run:
```bash
bundle exec rspec spec/features/race_telemetry_spec.rb -e "auto-selects the fastest lap on load" -e "clicking a lap isolates it and re-clicking returns to all laps"
```
Expected: FAIL. There is no `#lap-caption` element and no `data-selected-lap` attribute yet, and no lap is auto-selected, so the `have_css` expectations fail (e.g. `expected to find css "#lap-caption"`).

- [ ] **Step 3: Add the caption element to the view**

In `app/views/races/show.html.haml`, replace these two lines (currently at 22–23):

```haml
          %canvas.track-canvas.w-100{ width: 900, height: 480 }
          %button#set-start-finish.btn.btn-outline-primary.mt-3{ type: "button" } Set start/finish line
```

with:

```haml
          %canvas.track-canvas.w-100{ width: 900, height: 480 }
          .d-flex.align-items-center.justify-content-between.mt-3
            %span#lap-caption.fw-semibold.text-body-secondary
            %button#set-start-finish.btn.btn-outline-primary{ type: "button" } Set start/finish line
```

(The `mt-3` spacing moves from the button to the wrapping flex row.)

- [ ] **Step 4: Rewrite the track map selection logic**

Replace the entire contents of `app/packs/scripts/track_map.js` with:

```js
// Draws a telemetry racing line on a <canvas>, coloured by speed, supports
// click-to-set the start/finish line, and isolates a single selected lap.
function speedColor(speed, min, max) {
  const ratio = max > min ? (speed - min) / (max - min) : 0;
  const hue = ratio * 120; // 0=red (slow) -> 120=green (fast)
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
    // lap_id currently isolated on the canvas, or null for the full session.
    this.selectedLap = null;
    this.caption = document.getElementById("lap-caption");
    this.computeBounds();
    this.bindPlacement();
    this.bindLapSelection();
    this.selectDefaultLap(); // auto-select the best lap, then caption + draw
  }

  computeBounds() {
    const lats = this.samples.map((s) => s.lat);
    const lons = this.samples.map((s) => s.lon);
    this.minLat = Math.min(...lats); this.maxLat = Math.max(...lats);
    this.minLon = Math.min(...lons); this.maxLon = Math.max(...lons);
    this.pad = 30;

    // Project lat/lon onto a locally-planar metric so the track keeps its true
    // shape. A degree of latitude is a ~constant ground distance, but a degree
    // of longitude shrinks by cos(latitude) as meridians converge, so scale lon
    // by that factor before fitting. Then use a SINGLE uniform scale for both
    // axes (aspect-preserving) and letterbox the track in the leftover space,
    // rather than stretching each axis independently to fill the canvas.
    const midLat = (this.minLat + this.maxLat) / 2;
    this.lonScale = Math.cos((midLat * Math.PI) / 180); // lon degrees -> lat-equivalent degrees
    const w = this.canvas.width - this.pad * 2;
    const h = this.canvas.height - this.pad * 2;
    const lonSpan = ((this.maxLon - this.minLon) * this.lonScale) || 1;
    const latSpan = (this.maxLat - this.minLat) || 1;
    this.scale = Math.min(w / lonSpan, h / latSpan); // px per lat-equivalent degree
    this.offsetX = this.pad + (w - lonSpan * this.scale) / 2;
    this.offsetY = this.pad + (h - latSpan * this.scale) / 2;
  }

  project(lat, lon) {
    const x = this.offsetX + (lon - this.minLon) * this.lonScale * this.scale;
    const y = this.offsetY + (this.maxLat - lat) * this.scale; // canvas y grows downward
    return [x, y];
  }

  unproject(x, y) {
    const lon = this.minLon + (x - this.offsetX) / (this.lonScale * this.scale);
    const lat = this.maxLat - (y - this.offsetY) / this.scale;
    return [lat, lon];
  }

  draw() {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    if (this.samples.length < 2) return;

    // Speed colour uses the whole-session min/max so a colour means the same
    // speed on every lap, even when only one lap is drawn.
    const speeds = this.samples.map((s) => s.sp);
    const min = Math.min(...speeds), max = Math.max(...speeds);

    ctx.lineWidth = 5;
    ctx.lineCap = "round";
    for (let i = 1; i < this.samples.length; i++) {
      const a = this.samples[i - 1], b = this.samples[i];
      // When a lap is selected, draw only that lap's segments; samples with no
      // lap (warm-up, out/in-lap) are skipped. null selection draws everything.
      if (this.selectedLap !== null && b.lap !== this.selectedLap) continue;
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
      authenticity_token: document.querySelector('meta[name="csrf-token"]')?.content || "",
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

  bindLapSelection() {
    this.rows = Array.from(
      document.querySelectorAll(".lap-table tbody tr[data-lap-id]")
    );
    this.rows.forEach((row) => {
      row.style.cursor = "pointer";
      row.addEventListener("click", () => {
        const id = parseInt(row.dataset.lapId, 10);
        // Clicking the active lap again clears the selection (full session).
        this.setSelectedLap(this.selectedLap === id ? null : id);
      });
    });
  }

  selectDefaultLap() {
    const best = document.querySelector(
      ".lap-table tbody tr.table-success[data-lap-id]"
    );
    this.setSelectedLap(best ? parseInt(best.dataset.lapId, 10) : null);
  }

  setSelectedLap(id) {
    this.selectedLap = id;
    this.root.dataset.selectedLap = id === null ? "" : String(id);
    this.rows.forEach((r) =>
      r.classList.toggle(
        "table-active",
        id !== null && parseInt(r.dataset.lapId, 10) === id
      )
    );
    this.updateCaption();
    this.draw();
  }

  updateCaption() {
    if (!this.caption) return;
    if (this.selectedLap === null) {
      this.caption.textContent = "All laps";
      return;
    }
    const row = this.rows.find(
      (r) => parseInt(r.dataset.lapId, 10) === this.selectedLap
    );
    if (!row) {
      this.caption.textContent = "All laps";
      return;
    }
    const cells = row.querySelectorAll("td");
    const number = cells[0] ? cells[0].textContent.trim() : "";
    const time = cells[1] ? cells[1].textContent.trim() : "";
    this.caption.textContent = `Lap ${number} · ${time}`;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-track-map]").forEach((el) => new TrackMap(el));
});

export default TrackMap;
```

Key changes vs the old file: `highlightLap` → `selectedLap`; `bindLapHighlight()` → `bindLapSelection()` + `selectDefaultLap()` + `setSelectedLap()` + `updateCaption()`; `draw()` now `continue`s past non-selected segments instead of dimming them; the constructor calls `selectDefaultLap()` (which draws) instead of a bare `this.draw()`. `computeBounds`, `project`, `unproject`, `drawStartFinish`, `bindPlacement`, `submitLine` are unchanged.

- [ ] **Step 5: Run the new specs to verify they pass**

Run:
```bash
bundle exec rspec spec/features/race_telemetry_spec.rb -e "auto-selects the fastest lap on load" -e "clicking a lap isolates it and re-clicking returns to all laps"
```
Expected: PASS (2 examples, 0 failures). First run recompiles webpack — allow extra time.

- [ ] **Step 6: Run the whole feature file to confirm no regression**

Run:
```bash
bundle exec rspec spec/features/race_telemetry_spec.rb
```
Expected: PASS (all examples). The pre-existing `"clicking a lap row highlights it"` scenario still passes: its single lap has `best: false`, so nothing is auto-selected on load, and clicking the row still applies `table-active`.

- [ ] **Step 7: Commit**

```bash
git add app/packs/scripts/track_map.js app/views/races/show.html.haml spec/features/race_telemetry_spec.rb
git commit -m "Isolate selected lap on the track map instead of dimming"
```

---

## Task 2: Visual verification in the running app

Automated specs cover the DOM-observable selection state, but the actual canvas rendering (only one lap drawn; full session on deselect) can only be confirmed visually. Do this manual pass before considering the feature done.

**Files:** none (verification only).

- [ ] **Step 1: Start the app and asset server**

In two terminals:
```bash
bin/dev
```
```bash
bin/shakapacker-dev-server
```

- [ ] **Step 2: Open a race that has detected laps**

Sign in, open a race whose start/finish line is set and laps are detected (upload `public/short_example_telemetry_log.csv` and place the line if you need one).

- [ ] **Step 3: Confirm the behaviour**

Verify all of:
- On load, the canvas shows a **single** clean racing line (the best lap), the best lap's row is highlighted, and the caption reads `Lap N · <time>`.
- Clicking another lap row redraws the canvas to show **only** that lap and updates the caption.
- Clicking the highlighted row again returns to the **full session** (every lap drawn) and the caption reads `All laps`.
- Speed colours (red→green) look consistent between laps — a fast section is green whichever lap is shown.

- [ ] **Step 4: Run the full suite**

Run:
```bash
bundle exec rake
```
Expected: PASS (whole RSpec suite green).

---

## Self-review notes

- **Spec coverage:** selection model / `selectedLap` filter (Task 1 Step 4, `draw()`), default best-lap on load (`selectDefaultLap`, tested Step 1), full-session on `null` (`draw()` + deselect test), toggle/deselect (`setSelectedLap` + test), whole-session colour scale (`draw()` computes global min/max, comment), caption (view + `updateCaption` + tests), compare-later seam (single `b.lap === selectedLap` check, scalar `selectedLap`), no data/model changes (view + JS only). All covered.
- **No placeholders:** every step has concrete code/commands.
- **Type/name consistency:** `selectedLap`, `setSelectedLap`, `selectDefaultLap`, `bindLapSelection`, `updateCaption`, `this.rows`, `data-selected-lap`, `#lap-caption` used identically across the spec, the JS, and the view.
