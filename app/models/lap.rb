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
class Lap < ApplicationRecord
  belongs_to :race
  has_many :telemetry_samples, dependent: :nullify

  validates :number, :start_offset_ms, :end_offset_ms, :lap_time_ms, presence: true

  def formatted_time
    total_seconds = lap_time_ms / 1000.0
    minutes = (total_seconds / 60).floor
    seconds = total_seconds - minutes * 60
    format("%d:%06.3f", minutes, seconds)
  end
end
