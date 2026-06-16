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

    accept_confirm do
      click_link "Delete"
    end

    expect(page).to have_content("Race deleted.")
    expect(Race.where(id: race.id)).to be_empty
  end
end
