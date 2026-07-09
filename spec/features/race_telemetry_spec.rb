require "rails_helper"

RSpec.feature "Race telemetry", js: true do
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  let(:user) { create(:user) }
  before { login_as(user, scope: :user) }

  scenario "uploading a CSV parses it and draws the map" do
    visit new_race_path
    attach_file "Telemetry CSV", Rails.root.join("spec/factories/files/telemetry_sample.csv")
    click_button "Upload"

    expect(page).to have_css("#track-map .leaflet-container")
    expect(page).to have_content("Ready")
    expect(page).to have_content("No laps yet")
  end

  scenario "clicking a lap row highlights it" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.001, lon: -1.001, speed: 20)
    lap = create(:lap, race: race, number: 1)

    visit race_path(race)
    find("tr[data-lap-id='#{lap.id}']").click
    expect(page).to have_css("tr[data-lap-id='#{lap.id}'].table-active")
  end

  scenario "auto-selects the fastest lap on load" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.001, lon: -1.001, speed: 20)
    slow = create(:lap, race: race, number: 1, best: false)
    fast = create(:lap, race: race, number: 2, best: true, lap_time_ms: 80_000)

    visit race_path(race)

    expect(page).to have_css("tr[data-lap-id='#{fast.id}'].table-active")
    expect(page).to have_no_css("tr[data-lap-id='#{slow.id}'].table-active")
    expect(page).to have_css("#lap-caption", text: "Lap 2")
    expect(page).to have_css("#track-map[data-selected-lap='#{fast.id}']")
  end

  scenario "clicking a lap isolates it and re-clicking returns to all laps" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.001, lon: -1.001, speed: 20)
    lap1 = create(:lap, race: race, number: 1, best: true)
    lap2 = create(:lap, race: race, number: 2, best: false)

    visit race_path(race)
    expect(page).to have_css("#lap-caption", text: "Lap 1")

    find("tr[data-lap-id='#{lap2.id}']").click
    expect(page).to have_css("tr[data-lap-id='#{lap2.id}'].table-active")
    expect(page).to have_css("#lap-caption", text: "Lap 2")

    find("tr[data-lap-id='#{lap2.id}']").click
    expect(page).to have_no_css("tr.table-active")
    expect(page).to have_css("#lap-caption", text: "All laps")
  end

  scenario "satellite basemap toggles on and off, defaulting to off" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.001, lon: -1.001, speed: 20)

    visit race_path(race)

    expect(page).to have_css("#track-map[data-basemap='off']")

    click_button "Satellite"
    expect(page).to have_css("#track-map[data-basemap='on']")
    expect(page).to have_css("button#toggle-basemap.active[aria-pressed='true']")

    click_button "Satellite"
    expect(page).to have_css("#track-map[data-basemap='off']")
    expect(page).to have_css("button#toggle-basemap[aria-pressed='false']:not(.active)")
  end

  scenario "setting the start/finish line on the map triggers lap detection" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 100, lat: 53.002, lon: -1.002, speed: 20)

    visit race_path(race)
    click_button "Set start/finish line"
    expect(page).to have_button("Click two points for the line…")
    map = find("#track-map .leaflet-container")
    map.click(x: -150, y: 0)
    map.click(x: 150, y: 0)

    expect(page).to have_content("Detecting laps")
    expect(race.reload.start_finish_set?).to be(true)
  end

  scenario "renders the scrubber controls with a position/time readout" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 90_000, lat: 53.001, lon: -1.001, speed: 20)

    visit race_path(race)

    expect(page).to have_css("#scrub-play")
    expect(page).to have_css("#scrub-range")
    expect(page).to have_css("#scrub-readout", text: "0:00.000 / 1:30.000")
    expect(page).to have_css("#track-map[data-scrub-ms='0']")
  end

  scenario "scrubbing the slider updates the readout and data-scrub-ms" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 90_000, lat: 53.001, lon: -1.001, speed: 20)

    visit race_path(race)

    # End jumps a native range to its max (the full domain span).
    find("#scrub-range").send_keys(:end)

    expect(page).to have_css("#track-map[data-scrub-ms='90000']")
    expect(page).to have_css("#scrub-readout", text: "1:30.000 / 1:30.000")
  end

  scenario "the time domain follows the selected lap and resets on deselect" do
    race = create(:race, user: user, status: :ready, sample_count: 3)
    lap = create(:lap, race: race, number: 1, best: true, lap_time_ms: 90_000)
    create(:telemetry_sample, race: race, lap: lap, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, lap: lap, sequence: 1, offset_ms: 90_000, lat: 53.001, lon: -1.001, speed: 20)
    create(:telemetry_sample, race: race, sequence: 2, offset_ms: 120_000, lat: 53.002, lon: -1.002, speed: 5)

    visit race_path(race)

    # Best lap auto-selected on load: domain total is the lap's span.
    expect(page).to have_css("#scrub-readout", text: "0:00.000 / 1:30.000")

    # Deselect (click the active lap row): domain becomes the whole session.
    find("tr[data-lap-id='#{lap.id}']").click
    expect(page).to have_css("#scrub-readout", text: "0:00.000 / 2:00.000")
    expect(page).to have_css("#track-map[data-scrub-ms='0']")
  end

  scenario "play advances the dot in real time and pause freezes it" do
    race = create(:race, user: user, status: :ready, sample_count: 2)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)
    create(:telemetry_sample, race: race, sequence: 1, offset_ms: 90_000, lat: 53.001, lon: -1.001, speed: 20)

    visit race_path(race)

    find("#scrub-play").click
    expect(page).to have_css("#scrub-play[aria-pressed='true']")
    # Advanced past the start within the Capybara wait window.
    expect(page).to have_no_css("#track-map[data-scrub-ms='0']")

    find("#scrub-play").click
    expect(page).to have_css("#scrub-play[aria-pressed='false']")

    frozen = find("#track-map")["data-scrub-ms"]
    sleep 0.4
    expect(find("#track-map")["data-scrub-ms"]).to eq(frozen)
  end

  scenario "does not show scrubber controls when the map cannot mount" do
    race = create(:race, user: user, status: :ready, sample_count: 1)
    create(:telemetry_sample, race: race, sequence: 0, offset_ms: 0, lat: 53.0, lon: -1.0, speed: 10)

    visit race_path(race)

    expect(page).to have_content("Ready")
    expect(page).to have_no_css("#scrub-play")
    expect(page).to have_no_css("#scrub-range")
  end
end
