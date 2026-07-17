class AddMaterialNameToMaterialStocks < ActiveRecord::Migration[7.2]
  def change
    # "Наименование номенклатуры" из исходного файла выгрузки — полное
    # человекочитаемое название (колонка "Номенклатура" в той же выгрузке
    # обрезана до 20 символов). Поиск на форме задачи и тексты актов
    # используют именно это поле.
    add_column :material_stocks, :material_name, :string, limit: 500
  end
end
