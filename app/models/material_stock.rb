# /var/www/redmine/plugins/redmine_expense/app/models/material_stock.rb

class MaterialStock < ApplicationRecord
  self.table_name = 'material_stocks'
  
  validates :material_type, presence: true, length: { maximum: 500 }
  validates :brand, presence: true, length: { maximum: 500 }
  validates :model, presence: true, length: { maximum: 500 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :hash_key, presence: true, uniqueness: true

  before_validation :generate_hash_key

  scope :low_stock, -> { where('quantity < ? AND quantity > ?', 10, 0) }

  def generate_hash_key
    self.hash_key = Digest::MD5.hexdigest("#{material_type}|#{brand}|#{model}") if new_record?
  end

  def display_name
    "#{material_type} | #{brand} | #{model}"
  end

  def available_quantity
    quantity - reserved_quantity
  end

  def reserved_quantity
    IntermediateExpense.where(material_stock_id: id, status: 'pending').sum(:quantity_used)
  rescue
    0
  end

  def self.import_from_excel(file)
    errors = []
    imported = 0
    updated = 0
    skipped = 0
    skipped_reasons = []
    file_hashes = {}

    begin
      spreadsheet = Roo::Spreadsheet.open(file.path)
      header = spreadsheet.row(1)

      required_columns = ['Количество', 'Тип материала (Номенклатура)',
                         'Модель (Наименование модификации)',
                         'Бренд (Наименование поставщика)']

      unless required_columns.all? { |col| header.include?(col) }
        return { success: false, error: 'Неверная структура Excel-файла' }
      end

      col_index = {
        quantity: header.index('Количество'),
        material_type: header.index('Тип материала (Номенклатура)'),
        model: header.index('Модель (Наименование модификации)'),
        brand: header.index('Бренд (Наименование поставщика)')
      }

      Rails.logger.info "=== НАЧАЛО ИМПОРТА ==="
      Rails.logger.info "Всего строк в файле: #{spreadsheet.last_row - 1}"

      transaction do
        (2..spreadsheet.last_row).each do |i|
          row = spreadsheet.row(i)
          next if row.compact.empty?

          begin
            quantity = row[col_index[:quantity]].to_f
            material_type = row[col_index[:material_type]].to_s.strip
            model = row[col_index[:model]].to_s.strip
            brand = row[col_index[:brand]].to_s.strip

            # Проверка обязательных полей
            if material_type.blank? || model.blank? || brand.blank?
              skipped += 1
              skipped_reasons << "Строка #{i}: Пустые обязательные поля"
              Rails.logger.warn "Строка #{i}: Пропущена - пустые поля"
              next
            end

            # Пропускаем отрицательное количество
            if quantity < 0
              skipped += 1
              skipped_reasons << "Строка #{i}: Отрицательное количество (#{quantity})"
              Rails.logger.warn "Строка #{i}: Пропущена - отрицательное количество"
              next
            end

            # Проверка дубликатов в файле
            hash_key = Digest::MD5.hexdigest("#{material_type}|#{brand}|#{model}")
            if file_hashes[hash_key]
              skipped += 1
              skipped_reasons << "Строка #{i}: Дубликат в файле (строка #{file_hashes[hash_key]})"
              Rails.logger.warn "Строка #{i}: Дубликат в файле"
              next
            end
            file_hashes[hash_key] = i

            # Ищем существующий материал
            existing = find_by(hash_key: hash_key)
            
            if existing
              # Обновляем количество
              if existing.quantity != quantity
                existing.update!(quantity: quantity)
                updated += 1
                Rails.logger.info "Строка #{i}: Обновлен материал ##{existing.id} (было: #{existing.quantity}, стало: #{quantity})"
              else
                # Количество не изменилось - все равно обновляем updated_at
                existing.touch
                updated += 1
                Rails.logger.info "Строка #{i}: Обновлен материал ##{existing.id} (количество не изменилось, обновлена дата)"
              end
            else
              # Создаем новый материал
              create!(
                material_type: material_type,
                brand: brand,
                model: model,
                quantity: quantity,
                hash_key: hash_key
              )
              imported += 1
              Rails.logger.info "Строка #{i}: Создан новый материал (Тип:#{material_type}, Бренд:#{brand}, Модель:#{model})"
            end

          rescue => e
            errors << "Строка #{i}: #{e.message}"
            Rails.logger.error "Строка #{i}: ОШИБКА - #{e.message}"
          end
        end
      end

      Rails.logger.info "=== РЕЗУЛЬТАТЫ ИМПОРТА ==="
      Rails.logger.info "Импортировано: #{imported}"
      Rails.logger.info "Обновлено: #{updated}"
      Rails.logger.info "Пропущено: #{skipped}"
      Rails.logger.info "Ошибок: #{errors.count}"
      Rails.logger.info "========================"

    rescue => e
      Rails.logger.error "КРИТИЧЕСКАЯ ОШИБКА: #{e.message}"
      return { success: false, error: "Ошибка при чтении файла: #{e.message}" }
    end

    {
      success: true,
      imported: imported,
      updated: updated,
      skipped: skipped,
      skipped_reasons: skipped_reasons.first(20),
      errors: errors,
      total_in_file: spreadsheet.last_row - 1,
      total_in_db: MaterialStock.count
    }
  end
end