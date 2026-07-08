# Lap isolation on the track map

**Date:** 2026-07-04
**Status:** Approved, ready for implementation plan

## Problem

The track map currently draws every sample of a session at once, speed-coloured.
Clicking a lap row in the table **dims** the other laps to grey rather than
removing them. Because laps sit on top of each other, the dimmed view is still
hard to read — you can't cleanly tell one lap from another.

## Goal

Selecting a lap should render **only that lap** on the canvas, leaving the lap
list on the right intact. On load, the fastest lap is shown by default so the
user always lands on one clean racing line.

This also lays a clean foundation for a later feature: overlaying two or more
laps to compare them (the app's core "see where to improve" use case). That
comparison work is explicitly **out of scope here** — we build single-lap
isolation now, structured so comparison can be layered on without a rewrite.

## Scope

Front-end only:

- `app/packs/scripts/track_map.js` — the selection/render logic.
- `app/views/races/show.html.haml` (and/or `_lap_table.html.haml`) — a small
  caption showing the current selection.

No model, controller, route, or job changes. Everything the canvas needs is
already in the DOM:

- Each sample already carries its `lap` id (`s.lap`) in `data-samples`.
- The best lap row is already marked `table-success` and carries `data-lap-id`.
- The whole-session speed min/max are already computed inside `draw()`.

## Behaviour

### Selection model

- Replace the current `highlightLap` (dim-others) field with a `selectedLap`
  (show-only) filter holding a single lap id, or `null`.
- **`selectedLap === null` = "full session":** every segment draws, exactly like
  today's default. This is the deselected state.
- When `selectedLap` is set, `draw()` renders a segment only when its lap matches
  (`b.lap === selectedLap`). Segments with no lap id (warm-up rows, out-lap /
  in-lap) are excluded while a lap is selected.

### Default view (on load)

- Auto-select the best lap: read `data-lap-id` from the `.table-success` row,
  set it as `selectedLap`, and mark that row `table-active`.
- If there is no best lap row (e.g. laps not yet detected), fall back to
  `selectedLap = null` (full session / whatever is currently drawable).

### Toggle behaviour

- Clicking the currently active row deselects it → `selectedLap = null` → full
  session view.
- Clicking a different row switches selection to that lap.
- Exactly one row carries `table-active` at a time; none when in full-session
  view. (Same toggle shape as the existing `bindLapHighlight`, driving a filter
  instead of a dim.)

### Colour scale

- Unchanged. Speed colouring stays on the **whole-session** scale — the global
  `min`/`max` are computed once from all samples in `draw()`, so green means the
  same speed on every lap. Do **not** recompute the scale per selected lap.

### Caption

- Add a caption near the canvas reflecting the current selection, e.g.
  `Lap 3 · 1:42.1` when a lap is selected, or `All laps` in full-session view.
- Source the text from the selected row's existing cells (lap number, formatted
  time). Update it whenever `selectedLap` changes.

## Compare-later seam (not built now)

The single extension point is the render filter. Today:

```js
const visible = b.lap === this.selectedLap;   // or selectedLap === null => all
```

Multi-lap comparison later becomes:

- selection held in a `Set` of lap ids instead of a scalar,
- the filter `this.selectedLaps.has(b.lap)`,
- and a switch from speed-colour to a per-lap hue so overlaid laps are
  distinguishable.

`selectedLap` stays a scalar for now (YAGNI); the refactor to a Set is a few
lines when comparison is actually added. Building the single-lap filter is not
throwaway work — it is the foundation.

## Testing

Canvas pixels are not practically assertable, so the existing `js: true` feature
spec (`spec/features/race_telemetry_spec.rb`) verifies the user-visible selection
state that drives the same code path:

- On load, the best-lap row is `table-active`.
- Clicking a different lap row moves `table-active` to it.
- Clicking the active row again clears `table-active` (full-session view).

The caption text can be asserted alongside these transitions as a second
observable signal.

## Out of scope

- Overlaying / comparing multiple laps at once.
- Per-lap colour scales.
- Any change to lap detection, parsing, or persisted data.
- Leaflet basemap toggle (tracked separately).
