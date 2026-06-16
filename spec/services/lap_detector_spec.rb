require "rails_helper"

RSpec.describe LapDetector do
  # Start/finish line: a vertical segment at lon(x)=0, lat(y) from -1..1.
  let(:line) { { lat_a: -1.0, lon_a: 0.0, lat_b: 1.0, lon_b: 0.0 } }

  # Path crosses the line three times (=> two laps), each 2000 ms apart.
  # Points are {offset_ms:, lat:(y), lon:(x)}.
  let(:samples) do
    [
      { offset_ms: 0,    lat: 0.0, lon: -1.0 },
      { offset_ms: 1000, lat: 0.0, lon:  1.0 }, # cross #1 at t=500
      { offset_ms: 2000, lat: 0.5, lon:  1.0 },
      { offset_ms: 3000, lat: 0.5, lon: -1.0 }, # cross #2 at t=2500
      { offset_ms: 4000, lat: 0.0, lon: -1.0 },
      { offset_ms: 5000, lat: 0.0, lon:  1.0 }  # cross #3 at t=4500
    ]
  end

  it "detects laps between consecutive crossings" do
    laps = described_class.new(samples, **line).laps
    expect(laps.length).to eq(2)
    expect(laps.map { |l| l[:number] }).to eq([1, 2])
    expect(laps.map { |l| l[:lap_time_ms] }).to eq([2000, 2000])
    expect(laps.first).to include(start_offset_ms: 500, end_offset_ms: 2500)
  end

  it "returns no laps when the path never crosses the line" do
    away = samples.map { |s| s.merge(lon: s[:lon] + 100) }
    expect(described_class.new(away, **line).laps).to be_empty
  end

  it "ignores warm-up points at 0,0" do
    with_warmup = [{ offset_ms: -100, lat: 0.0, lon: 0.0 }] + samples
    laps = described_class.new(with_warmup, **line).laps
    expect(laps.length).to eq(2)
  end

  it "debounces jitter crossings closer than min_lap_ms" do
    # Three crossings in quick succession (jitter), then a clean one much later.
    jittery = [
      { offset_ms: 0,      lat: 0.0, lon: -1.0 },
      { offset_ms: 1000,   lat: 0.0, lon:  1.0 }, # cross ~500 (kept, first)
      { offset_ms: 2000,   lat: 0.0, lon: -1.0 }, # cross ~1500 (gap 1000, dropped)
      { offset_ms: 3000,   lat: 0.0, lon:  1.0 }, # cross ~2500 (gap 2000, dropped)
      { offset_ms: 20_000, lat: 0.0, lon: -1.0 }  # cross ~11500 (gap large, kept)
    ]
    laps = described_class.new(jittery, **line, min_lap_ms: 5_000).laps
    expect(laps.length).to eq(1)
  end
end
