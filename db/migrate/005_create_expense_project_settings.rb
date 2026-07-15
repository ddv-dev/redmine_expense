class CreateExpenseProjectSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :expense_project_settings do |t|
      t.integer :project_id, null: false
      t.text :manager_ids
      t.text :contributor_ids

      t.timestamps
    end

    add_index :expense_project_settings, :project_id, unique: true
  end
end
