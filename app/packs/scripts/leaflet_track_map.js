// Leaflet-based track map. Draws the racing line speed-coloured, isolates a
// selected lap, supports pan/zoom, an optional Esri satellite basemap
// (off by default to support offline), and click-to-place the start/finish
// line. Replaces scripts/track_map.js
import L from "leaflet";
import TrackScrubber from "./track_scrubber";

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
      .filter((s) => !(s.lat === 0 && s.lon === 0)); 
    this.startFinish = JSON.parse(root.dataset.startFinish || "{}");
    this.updateUrl = root.dataset.updateUrl;
    this.placing = null;
    this.selectedLap = null;
    this.caption = document.getElementById("lap-caption");
    this.root.dataset.basemap = "off";
    if (!this.container || this.samples.length < 2) return;

    this.initMap();
    this.buildSegments();
    this.buildStartFinish();
    this.bindBasemapToggle();
    this.bindPlacement();
    this.bindLapSelection();
    this.scrubber = new TrackScrubber(this);
    this.selectDefaultLap();
  }

  initMap() {
    this.map = L.map(this.container, { minZoom: 10, maxZoom: 19 });
    // One shared canvas renderer: thousands of segments stay a single fast
    // canvas draw instead of thousands of SVG nodes.
    this.renderer = L.canvas({ padding: 0.5 });
    this.lineGroup = L.layerGroup().addTo(this.map);
    this.trackBounds = L.latLngBounds(this.samples.map((s) => [s.lat, s.lon]));
    this.resetView();
    // Builds tile requests but doesnt add - the Satellite toggle adds/removes it
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
        L.DomEvent.disableClickPropagation(div);
        L.DomEvent.disableScrollPropagation(div);
        const btn = L.DomUtil.create("a", "", div);
        btn.href = "#";
        btn.title = "Reset view";
        btn.setAttribute("role", "button");
        btn.innerHTML = "&#8962;";
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
    // Speed colour uses the whole-session min/max so a colour means the same speed on every lap
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
    // dashed white line over solid black line for visibility on any basemap
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

  // Rebuilds the lineGroup to show only the selected lap (or all laps if none selected)
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

    // Leaflet's click event already excludes drag-ends, so panning while in placement mode does not place a point.
    this.map.on("click", (e) => {
      if (this.placing === null || this.placing.length >= 2) return;
      // This ensures that an accidental double click is ignored
      if (this.placing.length === 1 && e.latlng.equals(this.placing[0])) return;
      this.placing.push(e.latlng);
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
        // clicking the active lap again resets to full race.
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
    // switching laps keeps the user's pan/zoom to help comparison
    this.redraw();
    if (this.scrubber && this.scrubber.mounted) this.scrubber.handleSelectionChange();
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
