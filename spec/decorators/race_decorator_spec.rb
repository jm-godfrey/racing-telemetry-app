require "rails_helper"

RSpec.describe RaceDecorator do
  let(:user) { create(:user) }

  it "renders a themed status badge" do
    race = create(:race, user: user, status: :ready).decorate
    expect(race.status_badge).to include("badge")
    expect(race.status_badge).to include("Ready")
  end

  describe "#best_lap_display" do
    it "shows a dash when there is no best lap" do
      race = create(:race, user: user).decorate
      expect(race.best_lap_display).to eq("—")
    end

    it "shows the formatted best lap time" do
      race = create(:race, user: user)
      create(:lap, race: race, lap_time_ms: 101_234, best: true)
      expect(race.decorate.best_lap_display).to eq("1:41.234")
    end
  end

  it "renders an uploaded-ago string" do
    race = create(:race, user: user).decorate
    expect(race.uploaded_ago).to match(/ago\z/)
  end

  describe "#thumbnail_svg_points" do
    it "is nil when there are fewer than two located samples" do
      race = create(:race, user: user).decorate
      expect(race.thumbnail_svg_points).to be_nil
    end

    it "produces a space-separated points string from located samples" do
      race = create(:race, user: user)
      create(:telemetry_sample, race: race, sequence: 0, lat: 53.0, lon: -1.0)
      create(:telemetry_sample, race: race, sequence: 1, lat: 53.001, lon: -1.001)
      points = race.decorate.thumbnail_svg_points
      expect(points).to be_a(String)
      expect(points.split(" ").length).to eq(2)
      expect(points).to match(/\A[\d.,\s]+\z/)
    end
  end
end
