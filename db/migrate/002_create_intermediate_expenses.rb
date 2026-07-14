class CreateIntermediateExpenses < ActiveRecord::Migration[7.2]
  def change
    create_table :intermediate_expenses do |t|
      t.integer :issue_id, null: false
      t.integer :material_stock_id, null: false
      t.decimal :quantity_used, precision: 10, scale: 2, null: false
      t.integer :user_id, null: false
      t.integer :author_id, null: false
      t.string :status, null: false, default: 'pending'
      t.datetime :approved_at
      t.integer :approved_by

      t.timestamps
    end

    add_index :intermediate_expenses, :issue_id
    add_index :intermediate_expenses, :material_stock_id
    add_index :intermediate_expenses, :status
    add_index :intermediate_expenses, [:issue_id, :status]
  end
end
