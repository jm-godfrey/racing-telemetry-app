FactoryBot.define do
  factory :race do
    sequence(:name) { |n| "Race #{n}" }
    status { :pending }

    trait :with_csv do
      after(:build) do |race|
        race.csv_file.attach(
          io: File.open(Rails.root.join("spec/factories/files/telemetry_sample.csv")),
          filename: "telemetry_sample.csv",
          content_type: "text/csv"
        )
      end
    end
  end
end
