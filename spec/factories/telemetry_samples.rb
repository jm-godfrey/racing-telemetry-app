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
FactoryBot.define do
  factory :telemetry_sample do
    race
    sequence(:sequence) { |n| n }
    offset_ms { sequence * 100 }
    lat { 53.0 }
    lon { -1.0 }
    speed { 10.0 }
    accel_x { 0.1 }
    accel_y { 0.1 }
    accel_z { 0.98 }
  end
end
