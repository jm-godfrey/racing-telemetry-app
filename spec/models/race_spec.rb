require "rails_helper"

RSpec.describe Race do
  it "requires a name" do
    expect(build(:race, name: nil)).not_to be_valid
  end

  it "defaults to pending status" do
    expect(build(:race).status).to eq("pending")
  end

  describe "#start_finish_set?" do
    it "is false when coordinates are missing" do
      expect(build(:race).start_finish_set?).to be(false)
    end

    it "is true when all four coordinates are present" do
      race = build(:race, start_finish_lat_a: 1, start_finish_lon_a: 2,
                          start_finish_lat_b: 3, start_finish_lon_b: 4)
      expect(race.start_finish_set?).to be(true)
    end
  end
end
