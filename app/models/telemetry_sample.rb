# == Schema Information
#
# Table name: telemetry_samples
#
#  id        :bigint           not null, primary key
#  accel_x   :float
#  accel_y   :float
#  accel_z   :float
#  lat       :float
#  lon       :float
#  offset_ms :integer          not null
#  sequence  :integer          not null
#  speed     :float
#  lap_id    :bigint
#  race_id   :bigint           not null
#
# Indexes
#
#  index_telemetry_samples_on_lap_id                (lap_id)
#  index_telemetry_samples_on_race_id               (race_id)
#  index_telemetry_samples_on_race_id_and_sequence  (race_id,sequence)
#
# Foreign Keys
#
#  fk_rails_...  (lap_id => laps.id)
#  fk_rails_...  (race_id => races.id)
#
class TelemetrySample < ApplicationRecord
  belongs_to :race
  belongs_to :lap, optional: true

  # A sample has a usable GPS fix once lat/lon are not both zero
  # (the leading "warm-up" rows are 0,0 before the GPS locks).
  scope :located, -> { where.not(lat: 0, lon: 0) }
end
