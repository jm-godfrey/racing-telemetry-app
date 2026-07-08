// SUPERSEDED (2026-07-08) by leaflet_track_map.js and no longer imported by
// any entrypoint. Kept as a reference/fallback for the pre-Leaflet canvas
// renderer. It does NOT receive new features (satellite toggle, pan/zoom,
// and later the scrubber exist only in the Leaflet version).
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
