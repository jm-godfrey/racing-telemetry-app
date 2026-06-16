class TelemetrySample < ApplicationRecord
  belongs_to :race
  belongs_to :lap, optional: true

  # A sample has a usable GPS fix once lat/lon are not both zero
  # (the leading "warm-up" rows are 0,0 before the GPS locks).
  scope :located, -> { where.not(lat: 0, lon: 0) }
end
