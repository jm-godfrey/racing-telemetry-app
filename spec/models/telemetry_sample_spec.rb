require "rails_helper"

RSpec.describe TelemetrySample do
  it "belongs to a race" do
    expect(build(:telemetry_sample).race).to be_present
  end

  describe ".located" do
    it "excludes warm-up rows at 0,0" do
      race = create(:race)
      good = create(:telemetry_sample, race: race, lat: 53.0, lon: -1.0)
      create(:telemetry_sample, race: race, lat: 0, lon: 0)
      expect(race.telemetry_samples.located).to contain_exactly(good)
    end
  end
end
