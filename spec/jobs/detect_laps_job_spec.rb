require "rails_helper"

RSpec.describe DetectLapsJob do
  let(:race) do
    create(:race,
           start_finish_lat_a: -1.0, start_finish_lon_a: 0.0,
           start_finish_lat_b: 1.0,  start_finish_lon_b: 0.0)
  end

  # 3 crossings => 2 laps, ~40s each (well above the job's 5s jitter debounce).
  before do
    coords = [
      [0,       0.0, -1.0], [20_000, 0.0, 1.0], [40_000, 0.5, 1.0],
      [60_000,  0.5, -1.0], [80_000, 0.0, -1.0], [100_000, 0.0, 1.0]
    ]
    coords.each_with_index do |(t, lat, lon), i|
      create(:telemetry_sample, race: race, sequence: i, offset_ms: t,
                                lat: lat, lon: lon, speed: 10 + i)
    end
  end

  it "creates a Lap per detected lap and updates the race count" do
    DetectLapsJob.perform_now(race.id)
    expect(race.reload.laps.count).to eq(2)
    expect(race.lap_count).to eq(2)
  end

  it "flags the fastest lap as best" do
    DetectLapsJob.perform_now(race.id)
    expect(race.laps.where(best: true).count).to eq(1)
  end

  it "tags samples that fall inside a lap with its lap_id" do
    DetectLapsJob.perform_now(race.id)
    lap = race.laps.find_by(number: 1)
    tagged = race.telemetry_samples.where(lap_id: lap.id)
    expect(tagged).to be_present
  end

  it "is idempotent when run twice" do
    DetectLapsJob.perform_now(race.id)
    DetectLapsJob.perform_now(race.id)
    expect(race.reload.laps.count).to eq(2)
  end
end
