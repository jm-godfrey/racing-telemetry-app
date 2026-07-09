require "rails_helper"

RSpec.feature "Deleting a race", js: true do
  let(:user) { create(:user, username: "remover") }

  before { login_as(user, scope: :user) }

  scenario "a user deletes a race from the My Races table" do
    create(:race, user: user, name: "Disposable Lap")

    visit races_path
    expect(page).to have_content("Disposable Lap")

    accept_confirm do
      find("a[aria-label='Delete']").click
    end

    expect(page).to have_content("Race deleted.")
    expect(page).not_to have_content("Disposable Lap")
    expect(Race.where(name: "Disposable Lap")).to be_empty
  end

  scenario "a user deletes a race from the race detail page" do
    race = create(:race, user: user, name: "Detail Delete")

    visit race_path(race)
    expect(page).to have_content("Detail Delete")

    find("#race-options-menu").click
    accept_confirm do
      click_link "Delete race"
    end

    expect(page).to have_content("Race deleted.")
    expect(Race.where(id: race.id)).to be_empty
  end

  scenario "a user renames a race from the options menu" do
    race = create(:race, user: user, name: "Old Name")

    visit race_path(race)
    expect(page).to have_css(".race-title", text: "Old Name")

    find("#race-options-menu").click
    click_button "Rename"
    # Wait for the modal to finish opening before typing, and clear the
    # pre-filled name with backspaces so the new value replaces it cleanly.
    expect(page).to have_css("#rename-race-modal.show")

    within "#rename-race-modal" do
      fill_in "Race name", with: "New Name", fill_options: { clear: :backspace }
      click_button "Save"
    end

    expect(page).to have_content("Race renamed.")
    expect(page).to have_css(".race-title", text: "New Name")
    expect(race.reload.name).to eq("New Name")
  end
end
