class CreatePeriodActSignatures < ActiveRecord::Migration[7.2]
  def change
    create_table :period_act_signatures do |t|
      t.integer :period_act_id, null: false
      t.integer :user_id, null: false
      t.boolean :requested, null: false, default: true
      t.string :status, null: false, default: 'pending'
      t.datetime :signed_at

      t.timestamps
    end

    add_index :period_act_signatures, [:period_act_id, :user_id], unique: true, name: 'index_period_act_signatures_on_act_and_user'
  end
end
