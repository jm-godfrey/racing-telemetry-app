# == Schema Information
#
# Table name: races
#
#  id                 :bigint           not null, primary key
#  duration_ms        :integer
#  lap_count          :integer          default(0), not null
#  name               :string           not null
#  recorded_at        :datetime
#  sample_count       :integer          default(0), not null
#  start_finish_lat_a :float
#  start_finish_lat_b :float
#  start_finish_lon_a :float
#  start_finish_lon_b :float
#  status             :integer          default("pending"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
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
