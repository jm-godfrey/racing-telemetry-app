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
