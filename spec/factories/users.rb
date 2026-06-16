FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "driver#{n}" }
    password { "password123" }
  end
end
