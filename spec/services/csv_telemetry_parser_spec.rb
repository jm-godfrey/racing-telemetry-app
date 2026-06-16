require "rails_helper"

RSpec.describe CsvTelemetryParser do
  let(:csv) do
    <<~CSV
      timestamp,lat,lon,speed,accelX,accelY,accelZ
      1000,0,0,0,0,0,1
      1100,53.0,-1.0,5.0,0.1,0.2,0.98
    CSV
  end

  it "parses each row into a numeric hash" do
    rows = described_class.new(StringIO.new(csv)).rows
    expect(rows.length).to eq(2)
    expect(rows.first).to eq(
      timestamp: 1000, lat: 0.0, lon: 0.0, speed: 0.0,
      accel_x: 0.0, accel_y: 0.0, accel_z: 1.0
    )
    expect(rows.last[:lat]).to eq(53.0)
  end

  it "raises on a missing required header" do
    bad = "timestamp,lat,lon\n1000,0,0\n"
    expect { described_class.new(StringIO.new(bad)).rows }
      .to raise_error(CsvTelemetryParser::InvalidFormat, /missing/i)
  end
end
