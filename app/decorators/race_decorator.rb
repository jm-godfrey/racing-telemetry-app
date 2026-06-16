class RaceDecorator < ApplicationDecorator
  delegate_all

  STATUS_VARIANTS = {
    "pending" => "secondary",
    "processing" => "warning",
    "ready" => "success",
    "failed" => "danger"
  }.freeze

  def status_badge
    variant = STATUS_VARIANTS.fetch(object.status, "secondary")
    h.content_tag(:span, object.status.titleize, class: "badge text-bg-#{variant}")
  end

  def best_lap_display
    object.best_lap&.formatted_time || "—"
  end

  def uploaded_ago
    "#{h.time_ago_in_words(object.created_at)} ago"
  end

  # Inline-SVG polyline points for a mini track preview, projected into a
  # width x height viewBox. Returns nil when there's no usable track data.
  def thumbnail_svg_points(width: 100, height: 60, pad: 4)
    coords = object.telemetry_samples.located.order(:sequence).pluck(:lat, :lon)
    return nil if coords.length < 2

    step = [coords.length / 40, 1].max
    sampled = coords.each_slice(step).map(&:first)

    lats = sampled.map(&:first)
    lons = sampled.map(&:last)
    min_lat, max_lat = lats.minmax
    min_lon, max_lon = lons.minmax
    lat_span = (max_lat - min_lat).nonzero? || 1.0
    lon_span = (max_lon - min_lon).nonzero? || 1.0
    inner_w = width - pad * 2
    inner_h = height - pad * 2

    sampled.map do |lat, lon|
      x = pad + ((lon - min_lon) / lon_span) * inner_w
      y = pad + (1 - (lat - min_lat) / lat_span) * inner_h
      "#{x.round(1)},#{y.round(1)}"
    end.join(" ")
  end
end
