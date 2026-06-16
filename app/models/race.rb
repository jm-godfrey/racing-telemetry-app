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
class Race < ApplicationRecord
  has_one_attached :csv_file

  has_many :telemetry_samples, dependent: :delete_all
  has_many :laps, dependent: :delete_all

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  validates :name, presence: true

  # True once the user has placed all four start/finish coordinates.
  def start_finish_set?
    [start_finish_lat_a, start_finish_lon_a,
     start_finish_lat_b, start_finish_lon_b].all?(&:present?)
  end

  def best_lap
    laps.find_by(best: true)
  end
end
