require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) { create(:user, username: "speedy") }
  before { sign_in user }

  it "greets the user by name" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Welcome back, speedy")
  end

  it "shows the user's race count and only their recent races" do
    create(:race, user: user, name: "My Recent Race")
    create(:race, user: create(:user), name: "Someone Else Race")

    get root_path
    expect(response.body).to include("My Recent Race")
    expect(response.body).not_to include("Someone Else Race")
  end

  it "shows an empty state when the user has no races" do
    get root_path
    expect(response.body).to include("Upload your first race")
  end
end
