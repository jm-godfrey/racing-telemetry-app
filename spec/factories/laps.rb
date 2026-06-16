# == Schema Information
#
# Table name: laps
#
#  id              :bigint           not null, primary key
#  best            :boolean          default(FALSE), not null
#  end_offset_ms   :integer          not null
#  lap_time_ms     :integer          not null
#  number          :integer          not null
#  start_offset_ms :integer          not null
#  top_speed       :float
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  race_id         :bigint           not null
#
# Indexes
#
#  index_laps_on_race_id             (race_id)
#  index_laps_on_race_id_and_number  (race_id,number) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (race_id => races.id)
#
FactoryBot.define do
  factory :lap do
    race
    sequence(:number) { |n| n }
    start_offset_ms { 0 }
    end_offset_ms { 90_000 }
    lap_time_ms { 90_000 }
    top_speed { 120.0 }
    best { false }
  end
end
