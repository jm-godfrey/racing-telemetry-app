class CreateTelemetrySamples < ActiveRecord::Migration[8.0]
  def change
    create_table :telemetry_samples do |t|
      t.references :race, null: false, foreign_key: true
      t.bigint  :lap_id
      t.integer :offset_ms, null: false
      t.integer :sequence, null: false
      t.float :lat
      t.float :lon
      t.float :speed
      t.float :accel_x
      t.float :accel_y
      t.float :accel_z
    end
    add_index :telemetry_samples, [:race_id, :sequence]
    add_index :telemetry_samples, :lap_id
  end
end
