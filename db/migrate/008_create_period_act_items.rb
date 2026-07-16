class CreatePeriodActItems < ActiveRecord::Migration[7.2]
  def change
    create_table :period_act_items do |t|
      t.integer :period_act_id, null: false
      t.integer :expense_history_id, null: false

      t.timestamps
    end

    add_index :period_act_items, :period_act_id
    add_index :period_act_items, :expense_history_id
  end
end
