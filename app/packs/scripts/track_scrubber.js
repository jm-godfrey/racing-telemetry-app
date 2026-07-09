// Timeline scrubber + car dot for the Leaflet track map
import L from "leaflet";

// White ring + dark fill circle in the marker pane, which stacks above the
// overlay pane holding the racing-line canvas, so the dot is always on top.
const DOT_OPTIONS = {
  radius: 6,
  color: "#ffffff",
  weight: 2,
  fillColor: "#111111",
  fillOpacity: 1,
  interactive: false,
  pane: "markerPane",
};

class TrackScrubber {
  constructor(trackMap) {
    this.trackMap = trackMap;
    this.map = trackMap.map;
    this.root = trackMap.root;
    this.samples = trackMap.samples;

    
    this.mounted = false;
    this.strip = document.getElementById("scrubber");
    this.playButton = document.getElementById("scrub-play");
    this.range = document.getElementById("scrub-range");
    if (!this.strip || !this.playButton || !this.range || this.samples.length < 2) return;

    this.playing = false;
    this.rafId = null;
    this.relMs = 0; // current time, RELATIVE to the domain start 

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
    // "input" fires continuously while dragging, so the dot tracks the thumb live
    this.range.addEventListener("input", () => {
      if (this.playing) this.pause();
      this.setTime(Number(this.range.value));
    });
  }

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
    // Paint the red "played" portion of the track (WebKit reads this var; on
    // Firefox ::-moz-range-progress handles the fill natively).
    const pct = this.span > 0 ? (this.relMs / this.span) * 100 : 0;
    this.range.style.setProperty("--scrub-fill", `${pct}%`);
    const [lat, lon] = this.positionAt(this.domainStart + this.relMs);
    this.dot.setLatLng([lat, lon]);
  }

  // Linear interpolation of lat/lon at an abs offset time, between the
  // bracketing sample pair for smooth dot motion
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

  // Advance current time by real elapsed time
  tick(now) {
    if (!this.playing) return;
    const delta = now - this.lastFrame;
    this.lastFrame = now;
    const next = this.relMs + delta;
    if (next >= this.span) {
      this.setTime(this.span);
      this.pause();
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

  // Called by LeafletTrackMap whenever the isolated lap changes and resets the time to 0
  handleSelectionChange() {
    this.pause();
    this.setDomain();
    this.setTime(0);
  }
}

export default TrackScrubber;
