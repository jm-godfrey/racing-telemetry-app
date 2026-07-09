# Track scrubber with car dot

**Date:** 2026-07-08
**Status:** Approved, ready for implementation plan

## Problem

The track map shows *where* the car went but not *when*. There is no way to
follow the car around the lap, or to stop at a specific moment and see where
on the track it happened. This is the foundation for the app's core "see
where to improve" use case: a shared "current time" that a future data-graphs
feature will sync to (a cursor on a speed trace and a dot on the map pointing
at the same instant).

## Goal

A **timeline scrubber** under the Leaflet track map drives a **car dot**
along the racing line:

- Drag the slider → the dot moves to that moment; stop anywhere to analyse.
- Press **play** → the dot runs the lap in real elapsed time (1×); pause
  freezes it.
- The timeline spans the **selected lap** when one is isolated, or the
  **whole session** when not.
- Readout is **position + time only** (e.g. `0:34.200 / 2:47.378`) — data
  readouts (speed, g) arrive with the later graphs feature.

This is **spec 2 of 2** following the Leaflet migration (spec 1,
`2026-07-08-leaflet-track-map-design.md`). Everything renders on the Leaflet
map that migration delivered.

## Decisions made in brainstorming

- **Scrubber-first.** The slider is the core control and the single source
  of truth for "current time". Playback is a `requestAnimationFrame` loop
  driving the same value. Click-the-track-to-jump is a later add that will
  set the same value — out of scope now.
- **Play/pause at 1× only.** No speed multipliers (0.5×/2×/4×) until the
  graphs give watching at other speeds analytical value.
- **Simple dot, not a rotating car icon.** A high-contrast circle marker.
  Direction is obvious from motion; a directional icon is a drop-in marker
  swap later if wanted.
- **Interpolated motion.** The dot linearly interpolates lat/lon between
  bracketing GPS samples so playback glides at display refresh rate instead
  of stepping at the ~10 Hz sample rate.
- **Position + time readout only.** A speed/g readout was considered and
  rejected as crowding; the graphs feature owns data display.

## Architecture

**A new unit, not a bigger map class.** The Leaflet-migration review flagged
`LeafletTrackMap` as at its cohesion limit, so the scrubber is its own file:

- **Create: `app/packs/scripts/track_scrubber.js`** — a `TrackScrubber`
  class owning: timeline state (current time in ms, playing/paused), the
  slider + play button + readout DOM, the car dot marker, the rAF playback
  loop, and time→position interpolation.
- **Modify: `app/packs/scripts/leaflet_track_map.js`** — gains only a thin
  seam: exposes `map`, the filtered `samples`, and the current
  `selectedLap`; invokes a selection-changed callback from the existing
  `setSelectedLap` path; instantiates the scrubber. The map class knows
  nothing about time or playback.
- **Modify: `app/views/races/show.html.haml`** — the control strip markup
  (play button, range input, readout) under the map, above the caption row.

The selection-changed callback is the same seam the future graphs plug into:
they will observe the scrubber's current time, which is owned in one place.

**The car dot** is an `L.circleMarker` (white ring, dark fill, ~8 px radius)
in Leaflet's **marker pane** — which stacks above the overlay pane holding
the racing line's canvas, so the dot renders on top at every zoom with no
re-add ordering.

**Position lookup:** samples already carry `t` (offset ms). For a current
time, find the bracketing sample pair and linearly interpolate lat/lon.
Lap time domains are derived from the samples (min/max `t` of samples with
that lap id). **No controller, model, route, job, or serialized-data
changes.**

## Behaviour

### Time domain

- **Lap selected** → domain is that lap's `[start t, end t]`; slider and
  readout are lap-relative (`0:00.000` → lap time); the dot travels only
  that lap's path.
- **No selection** → domain is the whole session
  `[first sample t, last sample t]`; the dot travels everything, including
  out/in-laps (warm-up rows are already filtered out upstream).

### Domain changes

On any domain change (clicking a lap row, deselecting, best-lap auto-select
on load): playback **pauses** and current time **resets to the domain
start**. Carrying a mid-lap time across laps is only sometimes meaningful;
silently wrong is worse than predictably reset.

### Playback

- Play advances current time in real elapsed time (1×) via rAF, through the
  same code path as dragging the slider.
- Reaching the domain end pauses (no loop), leaving the dot at the end;
  play again restarts from the domain start.
- Dragging the slider while playing pauses playback.

### Initial state

On load, best lap auto-selected (existing behaviour) → scrubber at
`0:00.000`, paused, dot at the lap start. No laps → session domain. Map not
mounted (<2 usable samples) → no scrubber controls at all.

## Controls & UI

A control strip directly under the map, above the caption row:

```
[▶] ────────●──────────────────  0:34.200 / 2:47.378
```

- **Play/pause button:** small Bootstrap outline button; bootstrap-icons
  glyph flips play/pause; `aria-pressed` tracks state (same accessible
  toggle pattern as the Satellite button).
- **Slider:** native `<input type="range">`, full remaining width, stepped
  in milliseconds. Native = free keyboard support (arrows nudge, Home/End
  jump).
- **Readout:** `current / total`, formatted `M:SS.mmm` to match the lap
  table (JS reimplements the server's format).
- The dot updates on the slider's `input` event (live while dragging), not
  just `change`.
- The strip lives inside the existing card; Bootstrap flex utilities handle
  wrapping on small screens. At most a line or two of SCSS in
  `track_map.scss` if the slider needs width coaxing.

**State surface for tests/styling:** `#track-map` carries a `data-scrub-ms`
attribute mirroring current time (the scrubber's analogue of
`data-selected-lap`). It is **domain-relative** — `0` at the domain start,
matching the readout — so a domain change visibly resets it to `"0"`.

## Testing

Feature specs (`js: true`, in `spec/features/race_telemetry_spec.rb`), all
DOM-observable:

- **Controls render:** ready race with samples → play button, slider, and a
  `0:00.000 / <total>` readout exist.
- **Scrubbing updates state:** driving the range input (keyboard End/arrow
  keys) updates the readout and `data-scrub-ms`.
- **Domain switching:** lap selected → readout total is that lap's time;
  deselect → total becomes session length and `data-scrub-ms` resets.
- **Play/pause:** play flips `aria-pressed` and `data-scrub-ms` increases
  within a wait window; pause freezes it.
- **No-mount guard:** <2 usable samples → no scrubber controls.

## Edge cases

- **GPS gaps:** interpolation is per bracketing pair — the dot glides across
  a gap; no special handling.
- **Zoomed-in view:** the dot may leave the viewport while playing.
  Deliberately **no auto-follow camera** — it fights manual panning (same
  philosophy as no re-fit on lap switch).
- **Session mode start:** warm-up `(0,0)` rows are filtered before the
  scrubber sees samples, so the session domain starts at the first real fix.

## Out of scope

- Click-the-track-to-jump (layers on later; sets the same current-time
  value).
- Playback speed multipliers; auto-follow camera.
- Data readouts (speed/g) and the graphs feature itself.
- Deferred minors from spec 1 (Escape-to-cancel placement, disabling
  buttons on bail, `data-lap-*` row attributes) — none needed here.
- Any server-side change.
