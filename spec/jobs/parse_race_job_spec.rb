require "rails_helper"

RSpec.describe ParseRaceJob do
  let(:race) { create(:race, :with_csv) }

  it "creates one sample per CSV row with offsets from the first timestamp" do
    ParseRaceJob.perform_now(race.id)
    race.reload

    expect(race.telemetry_samples.count).to eq(5)
    first = race.telemetry_samples.order(:sequence).first
    expect(first.offset_ms).to eq(0)
    expect(race.telemetry_samples.order(:sequence).last.offset_ms).to eq(400)
  end

  it "marks the race ready and records stats" do
    ParseRaceJob.perform_now(race.id)
    race.reload

    expect(race).to be_ready
    expect(race.sample_count).to eq(5)
    expect(race.duration_ms).to eq(400)
  end

  it "is idempotent when run more than once" do
    ParseRaceJob.perform_now(race.id)
    ParseRaceJob.perform_now(race.id)
    race.reload

    expect(race.telemetry_samples.count).to eq(5)
    expect(race.sample_count).to eq(5)
  end

  it "marks the race failed when the CSV is malformed" do
    bad = create(:race)
    bad.csv_file.attach(io: StringIO.new("nope\n1\n"), filename: "bad.csv", content_type: "text/csv")
    ParseRaceJob.perform_now(bad.id)
    expect(bad.reload).to be_failed
  end
end
