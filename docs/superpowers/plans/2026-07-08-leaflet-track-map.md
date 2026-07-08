# Leaflet Track Map with Satellite Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-projected `<canvas>` track map with Leaflet — pan/zoom everywhere, an off-by-default Esri satellite-imagery toggle, and all current behaviour (speed-coloured line, lap isolation, caption, click-to-place start/finish) ported over.

**Architecture:** Leaflet is the single map engine. "Abstract" mode is Leaflet with no tile layer on a dark background (fully offline); the Satellite toggle adds/removes an Esri World Imagery tile layer. The racing line is one `L.polyline` per consecutive sample pair on a shared `L.canvas()` renderer, held in a `L.layerGroup` that is rebuilt when the selected lap changes. The old `track_map.js` stays on disk but is removed from the entrypoint imports.

**Tech Stack:** Leaflet ~1.9 (yarn, bundled by Shakapacker — no CDN), vanilla JS ES class, Hamlit view, SCSS, RSpec + Capybara `js: true` (headless Chrome).

**Spec:** `docs/superpowers/specs/2026-07-08-leaflet-track-map-design.md`

> **Git note (per CLAUDE.md):** do NOT run `git add`/`git commit` at any step. Leave the working tree unstaged; the user reviews and commits manually. Where a normal plan would commit, just report what changed.

---

## Background the engineer needs

- **Data flow:** `RacesController#show` builds `@samples_json` as `[{ t:, lat:, lon:, sp:, lap: }, ...]` (`lap` nullable). `app/views/races/show.html.haml` serializes it into `#track-map[data-samples]`, plus `data-start-finish` (`{lat_a, lon_a, lat_b, lon_b}`, values null until set) and `data-update-url` (the `PATCH /races/:id/start_finish` path). **None of this changes.**
- **Warm-up rows:** samples with `lat === 0 && lon === 0` are GPS-lock noise; filter them out before rendering (the old code does this too).
- **Lap table:** `app/views/races/_lap_table.html.haml` renders `table.lap-table`; each `tbody tr` has `data-lap-id`, the best lap's row also has class `table-success`. `td`s in order: lap number, formatted time, top speed.
- **Selection contract the feature specs assert:** the selected row carries `table-active`; `#track-map` carries `data-selected-lap` (`""` when none); `#lap-caption` reads `Lap N · <time>` or `All laps`; the best lap auto-selects on load. All of this must keep working identically.
- **Asset wiring:** the layout loads `javascript_pack_tag 'application'` and `stylesheet_pack_tag 'styles'`. JS imports go in `app/packs/entrypoints/application.js`; CSS imports go in `app/packs/entrypoints/styles.js`. Shakapacker bundles node_modules CSS (and the image urls inside it) fine.
- **Leaflet gotchas:** the map container must have a nonzero height *via CSS* before `L.map()` is called. Leaflet click events use `.lng`, not `.lon`. `map.on("click")` already ignores clicks that end a drag, so pan and click-to-place coexist for free.
- **Feature specs** are `js: true` (headless Chrome; webpack compiles on first run — slow first invocation). They must stay network-free: never assert on actual tile images, only on the `data-basemap` attribute.
- **Factory defaults:** `create(:lap, ...)` has `best: false` by default.

## File structure

- **Create:** `app/packs/scripts/leaflet_track_map.js` — the whole new map (mount, line, isolation, toggle, placement, reset control).
- **Create:** `app/packs/styles/track_map.scss` — container height + abstract-mode background.
- **Modify:** `app/packs/entrypoints/application.js` — swap the script import.
- **Modify:** `app/packs/entrypoints/styles.js` — add Leaflet CSS + the new SCSS.
- **Modify:** `app/views/races/show.html.haml` — canvas → div, add Satellite button.
- **Modify:** `app/packs/scripts/track_map.js` — top-of-file deprecation comment only.
- **Modify (tests):** `spec/features/race_telemetry_spec.rb` — selector updates + basemap-toggle scenario.
- **Modify:** `package.json` / `yarn.lock` — add `leaflet`.

---

## Task 1: Install Leaflet and wire the stylesheets

**Files:**
- Modify: `package.json`, `yarn.lock` (via yarn)
- Create: `app/packs/styles/track_map.scss`
- Modify: `app/packs/entrypoints/styles.js`

- [ ] **Step 1: Add the leaflet package**

```bash
yarn add leaflet@^1.9.4
```

Expected: `yarn.lock` updated, `leaflet` appears in `package.json` dependencies.

- [ ] **Step 2: Create the track-map stylesheet**

Create `app/packs/styles/track_map.scss` with exactly:

```scss
// Leaflet track map. The container MUST have a height before L.map() runs.
.track-map-leaflet {
  height: 480px;
}

// Abstract (tiles-off) mode: dark neutral background behind the racing line.
#track-map[data-basemap="off"] .leaflet-container {
  background: #212529;
}
```

- [ ] **Step 3: Import Leaflet CSS and the new stylesheet**

In `app/packs/entrypoints/styles.js`, append after the existing imports:

```js
import 'leaflet/dist/leaflet.css';
import '../styles/track_map';
```

- [ ] **Step 4: Verify webpack compiles**

```bash
bin/shakapacker
```

Expected: compiles with no errors (warnings about asset size are fine).

- [ ] **Step 5: Report** — dependencies and styles in place; nothing user-visible yet. Leave unstaged.

---

## Task 2: Write the failing feature specs

**Files:**
- Modify: `spec/features/race_telemetry_spec.rb`

- [ ] **Step 1: Update the two canvas-dependent scenarios and add the toggle scenario**

In `spec/features/race_telemetry_spec.rb`:

(a) In the `"uploading a CSV parses it and draws the map"` scenario, replace:

```ruby
    expect(page).to have_css("canvas.track-canvas")
```

with:

```ruby
    expect(page).to have_css("#track-map .leaflet-container")
```

(b) In the `"setting the start/finish line on the map triggers lap detection"` scenario, replace:

```ruby
    canvas = find("canvas.track-canvas")
    canvas.click(x: -150, y: 0)
    canvas.click(x: 150, y: 0)
```

with:

```ruby
    map = find("#track-map .leaflet-container")
    map.click(x: -150, y: 0)
    map.click(x: 150, y: 0)
```

(c) Add a new scenario after `"clicking a lap isolates it and re-clicking returns to all laps"`:

```ruby
  scenario "satellite basemap toggles on and off, defaulting to off" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.001, lon: -1.001, speed: 20)

    visit race_path(race)

    expect(page).to have_css("#track-map[data-basemap='off']")

    click_button "Satellite"
    expect(page).to have_css("#track-map[data-basemap='on']")

    click_button "Satellite"
    expect(page).to have_css("#track-map[data-basemap='off']")
  end
```

- [ ] **Step 2: Run the feature file to verify the right failures**

```bash
bundle exec rspec spec/features/race_telemetry_spec.rb
```

Expected: FAIL. The upload, start/finish, and new toggle scenarios fail (no `.leaflet-container`, no "Satellite" button, no `data-basemap`). The two lap-selection scenarios still PASS — they only touch the table/caption, which exist and are driven by the old JS for now.

---

## Task 3: Update the view

**Files:**
- Modify: `app/views/races/show.html.haml:22-25`

- [ ] **Step 1: Replace the canvas block**

In `app/views/races/show.html.haml`, replace:

```haml
          %canvas.track-canvas.w-100{ width: 900, height: 480 }
          .d-flex.align-items-center.justify-content-between.mt-3
            %span#lap-caption.fw-semibold.text-body-secondary
            %button#set-start-finish.btn.btn-outline-primary{ type: "button" } Set start/finish line
```

with:

```haml
          .track-map-leaflet.w-100
          .d-flex.align-items-center.justify-content-between.mt-3
            %span#lap-caption.fw-semibold.text-body-secondary
            %div
              %button#toggle-basemap.btn.btn-outline-secondary.me-2{ type: "button", "aria-pressed": "false" } Satellite
              %button#set-start-finish.btn.btn-outline-primary{ type: "button" } Set start/finish line
```

The `#track-map` wrapper and all its `data-*` attributes are untouched.

---

## Task 4: Write the Leaflet map and swap the entrypoint import

**Files:**
- Create: `app/packs/scripts/leaflet_track_map.js`
- Modify: `app/packs/entrypoints/application.js`
- Modify: `app/packs/scripts/track_map.js` (comment only)

- [ ] **Step 1: Create `app/packs/scripts/leaflet_track_map.js`**

Full contents:

```js
// Leaflet-based track map. Draws the racing line speed-coloured, isolates a
// selected lap, supports pan/zoom, an optional Esri satellite basemap
// (off by default -> fully offline), and click-to-place the start/finish
// line. Supersedes scripts/track_map.js (kept unwired as a fallback).
import L from "leaflet";

const ESRI_IMAGERY_URL =
  "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}";
const ESRI_ATTRIBUTION =
  "Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, " +
  "GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community";

function speedColor(speed, min, max) {
  const ratio = max > min ? (speed - min) / (max - min) : 0;
  const hue = ratio * 120; // 0=red (slow) -> 120=green (fast)
  return `hsl(${hue}, 80%, 50%)`;
}

class LeafletTrackMap {
  constructor(root) {
    this.root = root;
    this.container = root.querySelector(".track-map-leaflet");
    this.samples = JSON.parse(root.dataset.samples || "[]")
      .filter((s) => !(s.lat === 0 && s.lon === 0)); // GPS warm-up noise
    this.startFinish = JSON.parse(root.dataset.startFinish || "{}");
    this.updateUrl = root.dataset.updateUrl;
    this.placing = null; // null = not placing; array of latlngs while placing
    // lap_id currently isolated on the map, or null for the full session.
    this.selectedLap = null;
    this.caption = document.getElementById("lap-caption");
    this.root.dataset.basemap = "off"; // satellite tiles never load by default
    if (!this.container || this.samples.length < 2) return;

    this.initMap();
    this.buildSegments();
    this.buildStartFinish();
    this.bindBasemapToggle();
    this.bindPlacement();
    this.bindLapSelection();
    this.selectDefaultLap(); // auto-select best lap, set caption, draw
  }

  initMap() {
    this.map = L.map(this.container, { minZoom: 10, maxZoom: 19 });
    // One shared canvas renderer: thousands of segments stay a single fast
    // canvas draw instead of thousands of SVG nodes.
    this.renderer = L.canvas({ padding: 0.5 });
    this.lineGroup = L.layerGroup().addTo(this.map);
    this.trackBounds = L.latLngBounds(this.samples.map((s) => [s.lat, s.lon]));
    this.resetView();
    // Built but NOT added -- the Satellite toggle adds/removes it, so the
    // page makes no tile requests until the user opts in.
    this.tiles = L.tileLayer(ESRI_IMAGERY_URL, {
      attribution: ESRI_ATTRIBUTION,
      maxZoom: 19,
    });
    this.addResetControl();
  }

  resetView() {
    this.map.fitBounds(this.trackBounds.pad(0.1), { maxZoom: 18 });
  }

  addResetControl() {
    const self = this;
    const ResetControl = L.Control.extend({
      onAdd() {
        const div = L.DomUtil.create("div", "leaflet-bar");
        const btn = L.DomUtil.create("a", "", div);
        btn.href = "#";
        btn.title = "Reset view";
        btn.setAttribute("role", "button");
        btn.innerHTML = "&#8962;"; // house glyph
        L.DomEvent.on(btn, "click", (e) => {
          L.DomEvent.preventDefault(e);
          self.resetView();
        });
        return div;
      },
    });
    new ResetControl({ position: "topleft" }).addTo(this.map);
  }

  buildSegments() {
    // Speed colour uses the whole-session min/max so a colour means the same
    // speed on every lap, even when only one lap is drawn.
    const speeds = this.samples.map((s) => s.sp);
    const min = Math.min(...speeds);
    const max = Math.max(...speeds);
    this.segments = [];
    for (let i = 1; i < this.samples.length; i++) {
      const a = this.samples[i - 1];
      const b = this.samples[i];
      this.segments.push({
        lap: b.lap,
        line: L.polyline([[a.lat, a.lon], [b.lat, b.lon]], {
          color: speedColor(b.sp, min, max),
          weight: 5,
          lineCap: "round",
          renderer: this.renderer,
          interactive: false,
        }),
      });
    }
  }

  buildStartFinish() {
    // Dashed white line over a wider dark casing so it reads on both the
    // dark abstract background and bright satellite imagery. Built once;
    // redraw() re-adds them last so they always sit on top of the line.
    this.startFinishLines = [];
    const sf = this.startFinish;
    if (sf.lat_a == null || sf.lat_b == null) return;
    const coords = [[sf.lat_a, sf.lon_a], [sf.lat_b, sf.lon_b]];
    const shared = { dashArray: "6 4", renderer: this.renderer, interactive: false };
    this.startFinishLines.push(
      L.polyline(coords, { color: "#000000", weight: 4, ...shared }),
      L.polyline(coords, { color: "#ffffff", weight: 2, ...shared })
    );
  }

  // Rebuild the layer group for the current selection. null = full session;
  // segments with no lap id (warm-up, out/in-lap) are hidden while a lap is
  // selected because their lap (null) never equals a selected id.
  redraw() {
    this.lineGroup.clearLayers();
    this.segments
      .filter((seg) => this.selectedLap === null || seg.lap === this.selectedLap)
      .forEach((seg) => seg.line.addTo(this.lineGroup));
    this.startFinishLines.forEach((line) => line.addTo(this.lineGroup));
  }

  bindBasemapToggle() {
    const button = document.getElementById("toggle-basemap");
    if (!button) return;
    button.addEventListener("click", () => {
      const on = this.root.dataset.basemap !== "on";
      this.root.dataset.basemap = on ? "on" : "off";
      button.classList.toggle("active", on);
      button.setAttribute("aria-pressed", String(on));
      if (on) {
        this.tiles.addTo(this.map);
      } else {
        this.tiles.remove();
      }
    });
  }

  bindPlacement() {
    const button = document.getElementById("set-start-finish");
    if (!button) return;
    button.addEventListener("click", () => {
      this.placing = [];
      button.textContent = "Click two points for the line…";
      this.container.style.cursor = "crosshair";
    });

    // Leaflet's click event already excludes drag-ends, so panning while in
    // placement mode does not place a point.
    this.map.on("click", (e) => {
      if (this.placing === null || this.placing.length >= 2) return;
      this.placing.push(e.latlng);
      if (this.placing.length === 2) this.submitLine();
    });
  }

  submitLine() {
    const [p1, p2] = this.placing; // Leaflet latlngs: .lat / .lng (not .lon)
    const form = document.createElement("form");
    form.method = "post";
    form.action = this.updateUrl;
    const fields = {
      _method: "patch",
      authenticity_token: document.querySelector('meta[name="csrf-token"]')?.content || "",
      "race[start_finish_lat_a]": p1.lat,
      "race[start_finish_lon_a]": p1.lng,
      "race[start_finish_lat_b]": p2.lat,
      "race[start_finish_lon_b]": p2.lng,
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
    // Deliberately no re-fit: switching laps keeps the user's pan/zoom so
    // the same corner can be compared across laps.
    this.redraw();
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
  document.querySelectorAll("[data-track-map]").forEach((el) => new LeafletTrackMap(el));
});

export default LeafletTrackMap;
```

- [ ] **Step 2: Swap the entrypoint import**

In `app/packs/entrypoints/application.js`, replace:

```js
import "../scripts/track_map";
```

with:

```js
import "../scripts/leaflet_track_map";
```

- [ ] **Step 3: Mark the old file as superseded (do not delete it)**

At the very top of `app/packs/scripts/track_map.js`, add:

```js
// SUPERSEDED (2026-07-08) by leaflet_track_map.js and no longer imported by
// any entrypoint. Kept as a reference/fallback for the pre-Leaflet canvas
// renderer. It does NOT receive new features (satellite toggle, pan/zoom,
// and later the scrubber exist only in the Leaflet version).
```

- [ ] **Step 4: Run the feature file**

```bash
bundle exec rspec spec/features/race_telemetry_spec.rb
```

Expected: PASS (6 examples, 0 failures) — the three Task 2 scenarios now pass and the two lap-selection scenarios still pass against the Leaflet implementation.

If the start/finish scenario fails on the click coordinates: the map div is 480px tall and full card width; `(±150, 0)` from centre lands well inside the map and either side of the two-sample track after `fitBounds` padding, and each Leaflet click unprojects to a real latlng, so any two distinct clicks produce a valid line. Check instead that the "Satellite"/"Set start/finish line" buttons aren't overlapping the map (they sit below it).

---

## Task 5: Full suite and visual verification

**Files:** none (verification only).

- [ ] **Step 1: Run the whole suite**

```bash
bundle exec rake
```

Expected: PASS (33 examples — the previous 32 plus the new toggle scenario).

- [ ] **Step 2: Start the app**

In two terminals:

```bash
bin/dev
```

```bash
bin/shakapacker-dev-server
```

- [ ] **Step 3: Verify in the browser**

Open a race with detected laps (upload `public/short_example_telemetry_log.csv` and place the line if needed). Confirm:

- Map loads on a **dark background, no tiles**, whole track framed (best lap isolated, caption correct) — and the network tab shows **no tile requests**.
- Drag pans; wheel zooms; `+`/`−` and the ⌂ reset control work; reset re-frames the track.
- Clicking lap rows isolates/deselects exactly as before, **without** the view re-framing.
- "Satellite" toggles aerial imagery under the line (button shows pressed state, Esri attribution appears bottom-right); toggling off removes tiles and attribution and restores the dark background.
- Start/finish line renders white-dashed-over-dark and stays visible in both modes.
- "Set start/finish line" → crosshair → two clicks submits and reloads with laps re-detected; panning between the two clicks does not place a point.

- [ ] **Step 4: Report** — list changed files for the user to review and commit manually (per CLAUDE.md, no `git add`/`git commit`).

---

## Self-review notes

- **Spec coverage:** one-engine architecture (Task 4 `initMap`), offline default + no tile requests until opt-in (`tiles` built not added; verified in Task 5 step 3), satellite toggle + `data-basemap` (Task 3 view, Task 4 `bindBasemapToggle`, Task 2 scenario), pan/zoom + limits + reset control (`initMap`, `addResetControl`), fitBounds framing (`resetView`), per-segment speed colouring on shared canvas renderer (`buildSegments`), whole-session colour scale (comment in `buildSegments`), lap isolation + caption + `data-selected-lap` contract (`setSelectedLap`/`updateCaption`, existing specs), view preservation on lap switch (`setSelectedLap` comment), start/finish casing + always-on-top (`buildStartFinish` + `redraw` ordering), placement via `e.latlng` with drag-safe clicks (`bindPlacement`), `.lng` not `.lon` (`submitLine` comment), warm-up filter (constructor), <2-samples bail (constructor guard), attribution (tile layer option), old file kept unwired (Task 4 step 3), network-free tests (Task 2 asserts attributes only). All covered.
- **Placeholder scan:** every code step shows complete code; every command has expected output. Clean.
- **Type consistency:** `LeafletTrackMap`, `redraw()`, `buildSegments()`, `buildStartFinish()`, `resetView()`, `this.lineGroup`, `this.segments`, `this.startFinishLines`, `data-basemap`, `#toggle-basemap`, `.track-map-leaflet` used identically across Tasks 1–4 and the specs.
- **Commit steps intentionally absent** per the CLAUDE.md git rule; each task ends by leaving changes unstaged.
