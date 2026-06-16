require "rails_helper"

RSpec.feature "Dashboard journey", js: true do
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  scenario "a user uploads a race from the dashboard and opens it" do
    login_as(create(:user, username: "pilot"), scope: :user)
    visit root_path
    expect(page).to have_content("Welcome back, pilot")

    click_link "Upload a new race"
    attach_file "Telemetry CSV", Rails.root.join("spec/factories/files/telemetry_sample.csv")
    click_button "Upload"

    expect(page).to have_css("canvas.track-canvas")
    expect(page).to have_content("Ready")

    visit races_path
    expect(page).to have_content("telemetry_sample.csv")
  end

  scenario "a user cannot see another user's races" do
    alice = create(:user, username: "alice")
    create(:race, user: create(:user, username: "bob"), name: "Bob Secret Race")

    login_as(alice, scope: :user)
    visit races_path
    expect(page).not_to have_content("Bob Secret Race")
  end
end
