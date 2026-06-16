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
require "rails_helper"

RSpec.describe Lap do
  describe "#formatted_time" do
    it "renders milliseconds as M:SS.mmm" do
      expect(build(:lap, lap_time_ms: 101_234).formatted_time).to eq("1:41.234")
    end

    it "renders sub-minute laps" do
      expect(build(:lap, lap_time_ms: 5_678).formatted_time).to eq("0:05.678")
    end
  end
end
