require "csv"

class CsvTelemetryParser
  class InvalidFormat < StandardError; end

  # CSV header name => symbol we store it under.
  COLUMN_MAP = {
    "timestamp" => :timestamp,
    "lat" => :lat,
    "lon" => :lon,
    "speed" => :speed,
    "accelX" => :accel_x,
    "accelY" => :accel_y,
    "accelZ" => :accel_z
  }.freeze

  REQUIRED_HEADERS = COLUMN_MAP.keys.freeze

  def initialize(io)
    @io = io
  end

  def rows
    table = CSV.new(@io, headers: true, header_converters: ->(h) { h.strip }, skip_blanks: true)
    parsed = table.read
    validate_headers!(parsed.headers)

    # Filter out rows that are missing any required columns, and convert the values to the appropriate types.
    parsed.filter_map do |row|
      next if COLUMN_MAP.keys.any? { |header| row[header].to_s.strip.empty? }

      COLUMN_MAP.each_with_object({}) do |(header, key), out|
        out[key] = key == :timestamp ? row[header].to_i : row[header].to_f
      end
    end
  end

  private

  def validate_headers!(headers)
    missing = REQUIRED_HEADERS - headers
    return if missing.empty?

    raise InvalidFormat, "CSV is missing required columns: #{missing.join(', ')}"
  end
end
