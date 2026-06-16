class AddUserToRaces < ActiveRecord::Migration[8.0]
  def up
    # Dev data only — remove existing ownerless races and their children.
    execute "DELETE FROM telemetry_samples"
    execute "DELETE FROM laps"
    execute "DELETE FROM races"
    add_reference :races, :user, null: false, foreign_key: true
  end

  def down
    remove_reference :races, :user, foreign_key: true
  end
end
