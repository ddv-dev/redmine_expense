class AddCommitteeToExpenseProjectSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :expense_project_settings, :committee_ids, :text
    add_column :expense_project_settings, :chairman_id, :integer
  end
end
