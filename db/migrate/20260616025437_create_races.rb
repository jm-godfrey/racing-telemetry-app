class CreateRaces < ActiveRecord::Migration[8.0]
  def change
    create_table :races do |t|
      t.string  :name, null: false
      t.integer :status, null: false, default: 0
      t.datetime :recorded_at
      t.integer :duration_ms
      t.float :start_finish_lat_a
      t.float :start_finish_lon_a
      t.float :start_finish_lat_b
      t.float :start_finish_lon_b
      t.integer :sample_count, null: false, default: 0
      t.integer :lap_count, null: false, default: 0
      t.timestamps
    end
  end
end
