class ParseRaceJob < ApplicationJob
  queue_as :default

  def perform(race_id)
    race = Race.find(race_id)
    race.processing!

    rows = race.csv_file.open { |file| CsvTelemetryParser.new(file).rows }
    raise CsvTelemetryParser::InvalidFormat, "no rows" if rows.empty?

    first_ts = rows.first[:timestamp]
    records = rows.each_with_index.map do |row, i|
      {
        race_id: race.id,
        sequence: i,
        offset_ms: row[:timestamp] - first_ts,
        lat: row[:lat], lon: row[:lon], speed: row[:speed],
        accel_x: row[:accel_x], accel_y: row[:accel_y], accel_z: row[:accel_z]
      }
    end

    # Delete any existing telemetry samples for this race and insert
    race.telemetry_samples.delete_all
    TelemetrySample.insert_all(records)

    race.update!(
      status: :ready,
      sample_count: records.length,
      duration_ms: rows.last[:timestamp] - first_ts,
      recorded_at: Time.zone.at(first_ts / 1000.0)
    )
  rescue StandardError => e
    Rails.logger.error("ParseRaceJob failed for race #{race_id}: #{e.message}")
    race&.failed!
  end
end
