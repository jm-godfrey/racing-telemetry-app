require "rails_helper"

RSpec.describe "Race ownership", type: :request do
  it "redirects unauthenticated users to the login page" do
    get races_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows a user only their own races" do
    alice = create(:user)
    bob = create(:user)
    create(:race, user: alice, name: "Alice Race")
    create(:race, user: bob, name: "Bob Race")

    sign_in alice
    get races_path
    expect(response.body).to include("Alice Race")
    expect(response.body).not_to include("Bob Race")
  end

  it "forbids opening another user's race" do
    alice = create(:user)
    bob = create(:user)
    bob_race = create(:race, user: bob)

    sign_in alice
    get race_path(bob_race)
    expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
  end
end
