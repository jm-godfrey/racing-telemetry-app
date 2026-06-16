require "rails_helper"

RSpec.describe "Races", type: :request do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  let(:user) { create(:user) }
  before { sign_in user }

  it "lists races on the index" do
    create(:race, user: user, name: "Brands Hatch AM")
    get races_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Brands Hatch AM")
  end

  it "renders the upload form" do
    get new_race_path
    expect(response).to have_http_status(:ok)
  end

  it "creates a race from an uploaded CSV and enqueues parsing" do
    file = Rack::Test::UploadedFile.new(
      Rails.root.join("spec/factories/files/telemetry_sample.csv"), "text/csv"
    )
    expect {
      post races_path, params: { race: { csv_file: file } }
    }.to change(Race, :count).by(1)
    expect(ParseRaceJob).to have_been_enqueued
    expect(response).to redirect_to(race_path(Race.last))
    expect(Race.last.name).to eq("telemetry_sample.csv")
    expect(Race.last.user).to eq(user)
  end

  it "shows a race" do
    race = create(:race, user: user)
    get race_path(race)
    expect(response).to have_http_status(:ok)
  end

  it "destroys a race" do
    race = create(:race, user: user)
    expect { delete race_path(race) }.to change(Race, :count).by(-1)
    expect(response).to redirect_to(races_path)
  end

  it "uses the races index as the root page" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Races")
  end
end
