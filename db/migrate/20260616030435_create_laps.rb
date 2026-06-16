class CreateLaps < ActiveRecord::Migration[8.0]
  def change
    create_table :laps do |t|
      t.references :race, null: false, foreign_key: true
      t.integer :number, null: false
      t.integer :start_offset_ms, null: false
      t.integer :end_offset_ms, null: false
      t.integer :lap_time_ms, null: false
      t.float :top_speed
      t.boolean :best, null: false, default: false
      t.timestamps
    end
    add_index :laps, [:race_id, :number], unique: true

    # Now that the laps table exists, add the DB foreign key for the
    # telemetry_samples.lap_id column created in the previous task.
    add_foreign_key :telemetry_samples, :laps, column: :lap_id
  end
end
