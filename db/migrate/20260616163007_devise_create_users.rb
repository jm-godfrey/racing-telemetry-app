class DeviseCreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :encrypted_password, null: false, default: ""
      t.timestamps null: false
    end
    add_index :users, :username, unique: true
  end
end
