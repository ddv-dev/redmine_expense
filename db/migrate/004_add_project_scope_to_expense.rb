class AddProjectScopeToExpense < ActiveRecord::Migration[7.2]
  def up
    # Переход на отдельный склад для каждого проекта. По решению заказчика
    # существующие данные (общий склад без привязки к проекту) обнуляются —
    # дальше остатки заводятся заново отдельно в каждом проекте.
    execute 'DELETE FROM intermediate_expenses'
    execute 'DELETE FROM expense_histories'
    execute 'DELETE FROM material_stocks'

    remove_index :material_stocks, :hash_key
    add_column :material_stocks, :project_id, :integer, null: false
    add_index :material_stocks, [:project_id, :hash_key], unique: true, name: 'index_material_stocks_on_project_and_hash'
    add_index :material_stocks, [:project_id, :material_type], name: 'index_material_stocks_on_project_and_type'
  end

  def down
    remove_index :material_stocks, name: 'index_material_stocks_on_project_and_hash'
    remove_index :material_stocks, name: 'index_material_stocks_on_project_and_type'
    remove_column :material_stocks, :project_id
    add_index :material_stocks, :hash_key, unique: true
  end
end
