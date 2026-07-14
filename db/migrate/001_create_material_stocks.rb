class CreateMaterialStocks < ActiveRecord::Migration[7.2]
  def change
    create_table :material_stocks do |t|
      t.string :material_type, limit: 500, null: false
      t.string :brand, limit: 500, null: false
      t.string :model, limit: 500, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false, default: 0
      t.text :description
      t.string :hash_key, limit: 32, null: false

      t.timestamps
    end

    add_index :material_stocks, :hash_key, unique: true
    add_index :material_stocks, [:material_type, :brand, :model], name: 'index_material_stocks_on_type_brand_model'
  end
end
