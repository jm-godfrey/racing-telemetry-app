require "rails_helper"

RSpec.describe User do
  it "is valid with a username and password" do
    expect(build(:user)).to be_valid
  end

  it "requires a username" do
    expect(build(:user, username: nil)).not_to be_valid
  end

  it "requires a username of at least 3 characters" do
    expect(build(:user, username: "ab")).not_to be_valid
  end

  it "rejects a duplicate username case-insensitively" do
    create(:user, username: "Alice")
    expect(build(:user, username: "alice")).not_to be_valid
  end

  it "does not require an email" do
    user = build(:user)
    expect(user).to respond_to(:email_required?)
    expect(user.email_required?).to be(false)
  end
end
