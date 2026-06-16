require "rails_helper"

RSpec.feature "Race telemetry", js: true do
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  scenario "uploading a CSV parses it and draws the map" do
    visit new_race_path
    attach_file "Telemetry CSV", Rails.root.join("spec/factories/files/telemetry_sample.csv")
    click_button "Upload"

    expect(page).to have_css("canvas.track-canvas")
    expect(page).to have_content("Ready")
    expect(page).to have_content("No laps yet")
  end

  scenario "clicking a lap row highlights it" do
    race = create(:race, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.001, lon: -1.001, speed: 20)
    lap = create(:lap, race: race, number: 1)

    visit race_path(race)
    find("tr[data-lap-id='#{lap.id}']").click
    expect(page).to have_css("tr[data-lap-id='#{lap.id}'].table-active")
  end

  scenario "setting the start/finish line on the map triggers lap detection" do
    race = create(:race, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.002, lon: -1.002, speed: 20)

    visit race_path(race)
    click_button "Set start/finish line"
    canvas = find("canvas.track-canvas")
    canvas.click(x: -150, y: 0)
    canvas.click(x: 150, y: 0)

    expect(page).to have_content("Detecting laps")
    expect(race.reload.start_finish_set?).to be(true)
  end
end
