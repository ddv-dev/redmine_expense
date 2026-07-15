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
    # Составной индекс по (material_type, brand, model) с utf8mb4 и varchar(500)
    # превышает лимит MySQL InnoDB в 3072 байта на ключ (500*3*4 = 6000 байт),
    # поэтому индексируем только самую частую точку входа в каскадный выбор.
    add_index :material_stocks, :material_type
  end
end
