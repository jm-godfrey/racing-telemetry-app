# Leaflet track map with satellite toggle

**Date:** 2026-07-08
**Status:** Approved, ready for implementation plan

## Problem

The track map is a static, hand-projected `<canvas>` plot. It cannot pan or
zoom, and it shows the racing line in a vacuum — no roads, kerbs, or
surroundings to relate the line to. Both were wanted: interactive pan/zoom,
and an optional real-world view under the line.

Building these separately would mean two pan/zoom implementations (one
hand-rolled for the canvas, one from a map library for the basemap). Instead,
one engine renders everything.

## Goal

Replace the canvas renderer with **Leaflet** as the single map engine:

- Pan/zoom everywhere, from one implementation.
- A **satellite imagery toggle** (Esri World Imagery). **Off by default** —
  the default view is the abstract dark-background plot, fully offline.
- All current behaviour ports over: speed-coloured line, lap isolation,
  best-lap auto-select, caption, click-to-place start/finish line.

This is **spec 1 of 2**. Spec 2 (separate) adds a timeline scrubber and car
dot; it is built on the Leaflet map, which is why this migration lands first.

## Decisions made in brainstorming

- **One engine (Leaflet), not two.** The "abstract" mode is Leaflet with no
  tile layer, not the old canvas. Offline-with-tiles-off must always work.
- **Satellite imagery, not street map.** A drawn street map is redundant with
  the plotted line; aerial photography shows the actual tarmac/kerbs/grass.
  The toggle is a simple on/off, not a three-way.
- **Default off, no persistence.** Tiles only load when explicitly toggled on,
  every page load starts offline. No localStorage.
- **Old code kept unwired.** `app/packs/scripts/track_map.js` stays on disk as
  a reference/fallback but is removed from the entrypoint imports. It will not
  receive new features (the scrubber will exist only in the Leaflet version).

## Architecture

- **Dependency:** `leaflet` added via yarn, bundled locally by Shakapacker
  (JS + its CSS). No CDN — the page never needs the network unless the
  satellite toggle is on.
- **New file:** `app/packs/scripts/leaflet_track_map.js`, imported from
  `app/packs/entrypoints/application.js` in place of `track_map.js`.
- **View (`app/views/races/show.html.haml`):** the `<canvas>` becomes a `%div`
  Leaflet mounts into (fixed height, ~480px). The `#track-map[data-track-map]`
  root keeps its existing `data-samples`, `data-start-finish` and
  `data-update-url` attributes unchanged — serialization is reused as-is.
  Caption, lap table, and set-start/finish button all stay.
- **Projection:** Leaflet's standard Web Mercator CRS. It is conformal
  (locally shape-preserving), so the aspect-correctness previously built by
  hand (`cos(midLat)` lon scaling) is inherent, and tiles align automatically.
  On load, `fitBounds` of the samples with padding reproduces the current
  "whole track, letterboxed" framing — now pannable/zoomable.
- **No server-side changes:** no models, controllers, routes, or jobs.

## Rendering the racing line

- **Segments:** one `L.polyline([a, b], { color: speedColor(...) })` per
  consecutive sample pair, all attached to a single shared `L.canvas()`
  renderer (one fast canvas draw, not thousands of SVG nodes). The
  `speedColor` red→amber→green function carries over unchanged.
- **Colour scale:** whole-session speed min/max, computed once — a colour
  means the same speed on every lap, as now.
- **Lap isolation:** all segments live in one `L.layerGroup`. When
  `selectedLap` changes the group is cleared and rebuilt with only matching
  segments (`b.lap === selectedLap`; `null` = full session; unlapped
  warm-up/out-lap/in-lap samples hidden while a lap is selected). Lap-table
  click binding, `table-active` toggling, `data-selected-lap` attribute,
  best-lap auto-select and `#lap-caption` logic move over verbatim.
- **View preservation:** switching laps keeps the current pan/zoom (comparing
  the same corner across laps must not re-frame the map). `fitBounds` runs
  once on load and again only via the reset-view control.
- **Start/finish line:** dashed `L.polyline`, white with a dark casing so it
  reads on both the dark abstract background and bright satellite imagery.
- **Warm-up rows** (lat 0, lon 0) are filtered before rendering, as now.

## Interactions & controls

- **Pan/zoom:** Leaflet defaults (drag, wheel/pinch, `+`/`−` buttons). Max
  zoom capped at the imagery's limit (~19); min zoom sensible so the user
  can't get lost at world scale. A **reset view** control re-runs the
  fitBounds framing.
- **Set start/finish line:** button enters placement mode (crosshair cursor,
  button text changes); the next two true map clicks give `e.latlng` directly
  — the hand-rolled `unproject` disappears. Dragging stays enabled in
  placement mode; Leaflet's click event already excludes drag-ends, so a pan
  does not place a point. Two points → the same generated `_method=patch`
  form POST to `start_finish_race_path`; page reloads; `DetectLapsJob` runs.
- **Satellite toggle:** a toggle button labelled "Satellite" in the caption
  row (alongside the set-start/finish button), visually indicating its state
  (e.g. Bootstrap `active` class). Toggling on adds the Esri World Imagery `L.tileLayer` beneath the
  line; off removes it. The map background flips between the dark abstract
  colour (off) and neutral (on). The root element carries
  `data-basemap="off"`/`"on"` for styling and tests.
- **Attribution:** Leaflet's attribution control; the Esri credit (required
  by the free-tile licence) appears only while satellite is on — Leaflet
  handles this automatically when the layer is added/removed.

## Testing

Existing `js: true` feature specs keep passing with minimal edits: they
assert `table-active`, `#lap-caption`, and `data-selected-lap`, all
preserved. Selectors touching `canvas.track-canvas` change to the Leaflet
container (`#track-map .leaflet-container`); the start/finish placement spec
clicks the map div instead of the canvas.

New DOM-observable coverage:

- Map mounts: `#track-map .leaflet-container` exists for a ready race with
  samples.
- Toggle: page loads with `data-basemap="off"`; clicking "Satellite" sets
  `data-basemap="on"`; clicking again returns it to `"off"`. Asserting the
  attribute (not tile images) keeps the suite network-free and CI green.

## Edge cases

- **No samples / race not ready:** the view already gates rendering; JS also
  bails before `L.map()` with <2 samples — no empty grey map.
- **Tiles fail (offline, Esri down):** grey background behind the line;
  nothing else affected. Leaflet's default behaviour, no extra handling.

## Out of scope

- Timeline scrubber and car dot (spec 2 — next).
- Overlaying / comparing multiple laps.
- Street-map tiles, three-way toggle, toggle persistence.
- Any server-side change.
