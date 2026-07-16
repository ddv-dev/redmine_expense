class CreatePeriodActs < ActiveRecord::Migration[7.2]
  def change
    create_table :period_acts do |t|
      t.integer :project_id, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :chairman_id
      t.text :committee_ids
      t.text :requested_ids
      t.integer :created_by, null: false
      t.string :pdf_file

      t.timestamps
    end

    add_index :period_acts, :project_id
    add_index :period_acts, :status
  end
end
