class LapDetector
  Point = Struct.new(:x, :y, :t)

  # min_lap_ms debounces GPS jitter near the line: a crossing that follows the
  # previous one by less than this is treated as noise and ignored. 0 disables
  # the debounce, leaving pure geometric detection.
  def initialize(samples, lat_a:, lon_a:, lat_b:, lon_b:, min_lap_ms: 0)
    @points = samples
      .reject { |s| s[:lat].to_f.zero? && s[:lon].to_f.zero? }
      .map { |s| Point.new(s[:lon].to_f, s[:lat].to_f, s[:offset_ms].to_i) }
    @a = Point.new(lon_a.to_f, lat_a.to_f, nil)
    @b = Point.new(lon_b.to_f, lat_b.to_f, nil)
    @min_lap_ms = min_lap_ms
  end

  # => [{ number:, start_offset_ms:, end_offset_ms:, lap_time_ms: }, ...]
  def laps
    crossings = crossing_times
    crossings.each_cons(2).with_index(1).map do |(start_t, end_t), number|
      {
        number: number,
        start_offset_ms: start_t,
        end_offset_ms: end_t,
        lap_time_ms: end_t - start_t
      }
    end
  end

  private

  def crossing_times
    times = []
    @points.each_cons(2) do |p1, p2|
      next unless segments_intersect?(p1, p2, @a, @b)

      t = interpolate_time(p1, p2)
      next if times.any? && t - times.last < @min_lap_ms

      times << t
    end
    times
  end

  # Proper segment intersection via orientation tests. A sample lying exactly on
  # the line (a direction of 0) is treated as a non-crossing; at real GPS
  # resolution that is vanishingly unlikely and not worth collinear handling.
  def segments_intersect?(p1, p2, p3, p4)
    d1 = direction(p3, p4, p1)
    d2 = direction(p3, p4, p2)
    d3 = direction(p1, p2, p3)
    d4 = direction(p1, p2, p4)
    ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
  end

  # lon is used as x and lat as y with no cos(lat) scaling. The crossing sign
  # tests are invariant under positive scaling of an axis, so this does not
  # affect lap detection over the small area of a single circuit.
  def direction(a, b, c)
    (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y)
  end

  # Fraction along p1->p2 where it crosses line A-B, then lerp the timestamp.
  def interpolate_time(p1, p2)
    r = [p2.x - p1.x, p2.y - p1.y]
    s = [@b.x - @a.x, @b.y - @a.y]
    denom = cross(r, s)
    return p1.t if denom.zero?

    qp = [@a.x - p1.x, @a.y - p1.y]
    t = cross(qp, s) / denom
    (p1.t + t * (p2.t - p1.t)).round
  end

  def cross(u, v)
    u[0] * v[1] - u[1] * v[0]
  end
end
