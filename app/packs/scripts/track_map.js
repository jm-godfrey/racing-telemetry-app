// Draws a telemetry racing line on a <canvas>, coloured by speed, supports
// click-to-set the start/finish line, and highlights a selected lap.
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
    this.highlightLap = null;
    this.computeBounds();
    this.draw();
    this.bindPlacement();
    this.bindLapHighlight();
  }

  computeBounds() {
    const lats = this.samples.map((s) => s.lat);
    const lons = this.samples.map((s) => s.lon);
    this.minLat = Math.min(...lats); this.maxLat = Math.max(...lats);
    this.minLon = Math.min(...lons); this.maxLon = Math.max(...lons);
    this.pad = 30;
  }

  project(lat, lon) {
    const w = this.canvas.width - this.pad * 2;
    const h = this.canvas.height - this.pad * 2;
    const lonSpan = (this.maxLon - this.minLon) || 1;
    const latSpan = (this.maxLat - this.minLat) || 1;
    const x = this.pad + ((lon - this.minLon) / lonSpan) * w;
    const y = this.pad + (1 - (lat - this.minLat) / latSpan) * h;
    return [x, y];
  }

  unproject(x, y) {
    const w = this.canvas.width - this.pad * 2;
    const h = this.canvas.height - this.pad * 2;
    const lon = this.minLon + ((x - this.pad) / w) * (this.maxLon - this.minLon);
    const lat = this.minLat + (1 - (y - this.pad) / h) * (this.maxLat - this.minLat);
    return [lat, lon];
  }

  draw() {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    if (this.samples.length < 2) return;

    const speeds = this.samples.map((s) => s.sp);
    const min = Math.min(...speeds), max = Math.max(...speeds);

    ctx.lineWidth = 5;
    ctx.lineCap = "round";
    for (let i = 1; i < this.samples.length; i++) {
      const a = this.samples[i - 1], b = this.samples[i];
      const [x1, y1] = this.project(a.lat, a.lon);
      const [x2, y2] = this.project(b.lat, b.lon);
      const dimmed = this.highlightLap && b.lap !== this.highlightLap;
      ctx.strokeStyle = dimmed ? "rgba(120,120,120,0.25)" : speedColor(b.sp, min, max);
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

  bindLapHighlight() {
    document.querySelectorAll(".lap-table tbody tr[data-lap-id]").forEach((row) => {
      row.style.cursor = "pointer";
      row.addEventListener("click", () => {
        const id = parseInt(row.dataset.lapId, 10);
        this.highlightLap = this.highlightLap === id ? null : id;
        document.querySelectorAll(".lap-table tbody tr").forEach((r) => r.classList.remove("table-active"));
        if (this.highlightLap) row.classList.add("table-active");
        this.draw();
      });
    });
  }
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-track-map]").forEach((el) => new TrackMap(el));
});

export default TrackMap;
