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
  const totalMs = Math.round(ms);
  const minutes = Math.floor(totalMs / 60000);
  const seconds = (totalMs % 60000) / 1000;
  return `${minutes}:${seconds.toFixed(3).padStart(6, "0")}`;
}

class TrackScrubber {
  constructor(trackMap) {
    this.trackMap = trackMap;
    this.map = trackMap.map;
    this.root = trackMap.root;
    this.samples = trackMap.samples; // already filtered + time-ordered

    // A JS constructor's bare `return` still yields a truthy `this`, so
    // `if (this.scrubber)` can't tell a fully-built scrubber from one that
    // bailed here. Callers check `this.mounted` instead.
    this.mounted = false;
    this.strip = document.getElementById("scrubber");
    this.playButton = document.getElementById("scrub-play");
    this.range = document.getElementById("scrub-range");
    this.readout = document.getElementById("scrub-readout");
    if (!this.strip || !this.playButton || !this.range || !this.readout || this.samples.length < 2) return;

    this.playing = false;
    this.rafId = null;
    this.relMs = 0; // current time, RELATIVE to the domain start (0..span)

    this.dot = L.circleMarker(
      [this.samples[0].lat, this.samples[0].lon],
      DOT_OPTIONS
    ).addTo(this.map);

    this.tick = this.tick.bind(this);
    this.setDomain();
    this.setTime(0);
    this.bindControls();
    this.updatePlayButton();
    this.strip.classList.remove("d-none");
    this.mounted = true;
  }

  bindControls() {
    this.playButton.addEventListener("click", () => this.togglePlay());
    // "input" (not just "change") fires continuously while dragging, so the
    // dot tracks the thumb live. Dragging while playing pauses playback.
    this.range.addEventListener("input", () => {
      if (this.playing) this.pause();
      this.setTime(Number(this.range.value));
    });
  }

  // The samples that make up the current time domain: the isolated lap's
  // samples when one is selected, otherwise the whole session. Falls back to
  // the session if a lap somehow has fewer than 2 samples.
  domainSamplesFor() {
    const lap = this.trackMap.selectedLap;
    if (lap === null) return this.samples;
    const inLap = this.samples.filter((s) => s.lap === lap);
    return inLap.length >= 2 ? inLap : this.samples;
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
        const segmentSpan = b.t - a.t || 1;
        const f = (absMs - a.t) / segmentSpan;
        return [a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f];
      }
    }
    return [last.lat, last.lon];
  }

  play() {
    if (this.playing || this.span <= 0) return;
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
