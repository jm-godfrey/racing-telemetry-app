require "rails_helper"

RSpec.feature "Authentication", js: true do
  scenario "a visitor signs up and lands on the dashboard" do
    visit new_user_registration_path
    fill_in "Username", with: "speedy"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    click_button "Create account"

    expect(page).to have_content("Welcome back, speedy")
  end

  scenario "an existing user logs in" do
    create(:user, username: "racer", password: "password123")
    visit new_user_session_path
    fill_in "Username", with: "racer"
    fill_in "Password", with: "password123"
    click_button "Log in"

    expect(page).to have_content("Welcome back, racer")
  end

  scenario "a logged-in user can log out" do
    login_as(create(:user, username: "outgoing"), scope: :user)
    visit root_path
    click_button "Log out"

    expect(page).to have_content("Log in")
  end
end
