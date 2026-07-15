require 'roo'
require 'digest'

class ImportForm
  include ActiveModel::Model
  
  attr_accessor :file
  
  validates :file, presence: true
  
  def parse_file(file_path = nil)
    file_to_read = file_path || (file.present? ? file.path : nil)
    return { data: [], errors: ['Файл не выбран'], skipped_details: [] } if file_to_read.blank?
    
    data = []
    errors = []
    skipped = 0
    skipped_details = []
    merged = 0
    index_by_hash = {}
    
    begin
      workbook = Roo::Excelx.new(file_to_read)
      sheet = workbook.sheet(0)
      
      sheet.each_with_index do |row, index|
        next if index == 0
        
        quantity = row[0].to_s.strip
        material_type = row[1].to_s.strip
        model = row[4].to_s.strip
        brand = row[6].to_s.strip
        
        # Проверяем обязательные поля
        skip_reasons = []
        
        if material_type.blank?
          skip_reasons << "пустая номенклатура"
        end
        
        if model.blank?
          skip_reasons << "пустая модификация"
        end

        if brand.blank?
          skip_reasons << "пустое наименование поставщика"
        end
        
        if quantity.blank?
          skip_reasons << "пустое количество"
        end
        
        if skip_reasons.any?
          skipped += 1
          skipped_details << {
            row_number: index + 1,
            material_type: material_type,
            model: model,
            brand: brand,
            quantity: quantity,
            reasons: skip_reasons,
            raw_data: row.compact.join(' | ')
          }
          next
        end
        
        # Преобразуем количество
        begin
          quantity = quantity.gsub(',', '.').to_f
        rescue
          skipped += 1
          skipped_details << {
            row_number: index + 1,
            material_type: material_type,
            model: model,
            brand: brand,
            quantity: quantity,
            reasons: ["ошибка преобразования количества: #{quantity.inspect}"],
            raw_data: row.compact.join(' | ')
          }
          next
        end
        
        if quantity <= 0
          skipped += 1
          skipped_details << {
            row_number: index + 1,
            material_type: material_type,
            model: model,
            brand: brand,
            quantity: quantity,
            reasons: ["количество равно #{quantity}"],
            raw_data: row.compact.join(' | ')
          }
          next
        end
        
        hash_key = MaterialStock.build_hash_key(material_type, brand, model)

        # Один и тот же материал в файле часто встречается несколько раз —
        # это отдельные партии прихода одного и того же товара (разные даты,
        # разный "Код партии"), а не ошибочные дубли. Плагин хранит только
        # суммарный остаток по материалу, поэтому такие строки складываются,
        # а не отбрасываются — иначе часть количества молча терялась бы.
        if index_by_hash.key?(hash_key)
          existing_item = data[index_by_hash[hash_key]]
          existing_item[:quantity] += quantity
          existing_item[:merged_rows] << (index + 1)
          merged += 1
          next
        end

        index_by_hash[hash_key] = data.size

        data << {
          material_type: material_type[0..499],
          brand: brand[0..499],
          model: model[0..499],
          quantity: quantity,
          hash_key: hash_key,
          row_number: index + 1,
          merged_rows: []
        }
      end
      
    rescue => e
      errors << "Ошибка при чтении файла: #{e.message}"
    end
    
    { data: data, errors: errors, skipped: skipped, skipped_details: skipped_details, merged: merged }
  end
  
  def preview_from_data(data, project_id)
    preview_data = []
    mismatches = []

    data.each do |item|
      hash_key = item[:hash_key] || item['hash_key']
      existing = MaterialStock.find_by(hash_key: hash_key, project_id: project_id)
      
      quantity = item[:quantity] || item['quantity']
      material_type = item[:material_type] || item['material_type']
      brand = item[:brand] || item['brand']
      model = item[:model] || item['model']
      row_number = item[:row_number] || item['row_number']
      
      if existing
        if existing.quantity != quantity
          mismatches << {
            material: existing.display_name,
            current_quantity: existing.quantity,
            new_quantity: quantity,
            material_stock_id: existing.id,
            hash_key: hash_key
          }
        end
        preview_data << {
          material_type: material_type,
          brand: brand,
          model: model,
          quantity: quantity,
          hash_key: hash_key,
          row_number: row_number,
          status: 'exists',
          current_quantity: existing.quantity,
          material_stock_id: existing.id
        }
      else
        preview_data << {
          material_type: material_type,
          brand: brand,
          model: model,
          quantity: quantity,
          hash_key: hash_key,
          row_number: row_number,
          status: 'new',
          current_quantity: nil,
          material_stock_id: nil
        }
      end
    end
    
    {
      data: preview_data,
      mismatches: mismatches,
      total: data.size,
      existing: preview_data.select { |d| d[:status] == 'exists' }.size,
      new: preview_data.select { |d| d[:status] == 'new' }.size,
      errors: []
    }
  end
  
  # keep_current: true  -> для позиций с расхождением количества оставляем текущий остаток в БД
  # keep_current: false -> перезаписываем остаток значением из файла (по умолчанию)
  def import_from_data!(preview_result, project_id, keep_current: false)
    updated_count = 0
    created_count = 0
    kept_count = 0
    errors = []
    mismatched_ids = (preview_result[:mismatches] || []).map { |m| m[:material_stock_id] || m['material_stock_id'] }.to_set

    preview_result[:data].each_with_index do |item, index|
      begin
        if item[:status] == 'exists'
          material = MaterialStock.find_by(id: item[:material_stock_id], project_id: project_id)
          raise ActiveRecord::RecordNotFound, "материал не найден в этом проекте" unless material

          if keep_current && mismatched_ids.include?(material.id)
            kept_count += 1
            next
          end

          if material.update(quantity: item[:quantity])
            updated_count += 1
          else
            errors << "Ошибка обновления #{material.display_name}: #{material.errors.full_messages.join(', ')}"
          end
        else
          existing = MaterialStock.find_by(hash_key: item[:hash_key], project_id: project_id)

          if existing
            if existing.update(quantity: item[:quantity])
              updated_count += 1
            end
          else
            material = MaterialStock.new(
              project_id: project_id,
              material_type: item[:material_type],
              brand: item[:brand],
              model: item[:model],
              quantity: item[:quantity],
              hash_key: item[:hash_key]
            )

            if material.save
              created_count += 1
            else
              errors << "Ошибка создания #{item[:material_type]} | #{item[:brand]}: #{material.errors.full_messages.join(', ')}"
            end
          end
        end
      rescue => e
        errors << "Исключение на строке #{index + 1}: #{e.message}"
      end
    end
    
    {
      success: errors.empty?,
      updated_count: updated_count,
      created_count: created_count,
      kept_count: kept_count,
      total: preview_result[:total],
      errors: errors
    }
  end
  
  def find_mismatches(preview_result)
    preview_result[:mismatches] || []
  end
end
