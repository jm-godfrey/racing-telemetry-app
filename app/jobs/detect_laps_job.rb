class DetectLapsJob < ApplicationJob
  queue_as :default

  # Crossings closer together than this are treated as GPS jitter, not real laps.
  MIN_LAP_MS = 5_000

  def perform(race_id)
    race = Race.find(race_id)
    return unless race.start_finish_set?

    samples = race.telemetry_samples.located.order(:sequence)
                  .pluck(:offset_ms, :lat, :lon)
                  .map { |o, la, lo| { offset_ms: o, lat: la, lon: lo } }

    detected = LapDetector.new(
      samples,
      lat_a: race.start_finish_lat_a, lon_a: race.start_finish_lon_a,
      lat_b: race.start_finish_lat_b, lon_b: race.start_finish_lon_b,
      min_lap_ms: MIN_LAP_MS
    ).laps

    Race.transaction do
      race.telemetry_samples.update_all(lap_id: nil)
      race.laps.delete_all

      created = detected.map do |lap|
        record = race.laps.create!(
          number: lap[:number],
          start_offset_ms: lap[:start_offset_ms],
          end_offset_ms: lap[:end_offset_ms],
          lap_time_ms: lap[:lap_time_ms]
        )
        race.telemetry_samples
            .where(offset_ms: lap[:start_offset_ms]..lap[:end_offset_ms])
            .update_all(lap_id: record.id)
        record.update!(top_speed: record.telemetry_samples.maximum(:speed))
        record
      end

      created.min_by(&:lap_time_ms)&.update!(best: true)
      race.update!(lap_count: created.length)
    end
  end
end
