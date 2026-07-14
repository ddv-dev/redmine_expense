class CreateExpenseHistories < ActiveRecord::Migration[7.2]
  def change
    create_table :expense_histories do |t|
      t.integer :issue_id, null: false
      t.integer :material_stock_id, null: false
      t.decimal :quantity_used, precision: 10, scale: 2, null: false
      t.integer :user_id, null: false
      t.integer :closed_by, null: false
      t.datetime :closed_at, null: false
      t.boolean :pdf_generated, null: false, default: false
      t.string :pdf_file

      t.timestamps
    end

    add_index :expense_histories, :issue_id
    add_index :expense_histories, :material_stock_id
    add_index :expense_histories, :closed_at
    add_index :expense_histories, [:issue_id, :material_stock_id], name: 'index_expense_histories_on_issue_and_material'
  end
end
