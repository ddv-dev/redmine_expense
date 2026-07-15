require "securerandom"
require "json"

class ImportController < ApplicationController
  include ExpenseAuthorization

  before_action { require_expense_permission(:manage_expense_stock) }

  def new
    @import = ImportForm.new
    cleanup_old_import_files
  end

  def preview
    @import = ImportForm.new(import_params)
    
    if @import.valid?
      temp_file_path = save_uploaded_file(@import.file)
      result = @import.parse_file(temp_file_path)
      
      if result[:errors].any?
        render json: { success: false, errors: result[:errors] }
        File.delete(temp_file_path) if File.exist?(temp_file_path)
        return
      end
      
      data_id = SecureRandom.hex(16)
      save_import_data(data_id, result[:data])
      
      preview_result = @import.preview_from_data(result[:data])
      mismatches = @import.find_mismatches(preview_result)
      
      File.delete(temp_file_path) if File.exist?(temp_file_path)
      
      render json: {
        success: true,
        data_id: data_id,
        preview: preview_result,
        mismatches: mismatches,
        total: preview_result[:total],
        existing: preview_result[:existing],
        new: preview_result[:new],
        skipped: result[:skipped],
        skipped_details: result[:skipped_details],
        merged: result[:merged]
      }
    else
      render json: { success: false, errors: @import.errors.full_messages }
    end
  rescue => e
    Rails.logger.error "Preview error: #{e.message}"
    render json: { success: false, errors: [e.message] }
  end

  def confirm
    data_id = params[:data_id]

    unless data_id.present? && data_id.match?(/\A[a-f0-9]{32}\z/)
      render json: { success: false, errors: ['Данные не найдены'] }
      return
    end

    data_file = import_data_path(data_id)

    if !File.exist?(data_file)
      render json: { success: false, errors: ['Данные не найдены'] }
      return
    end

    import_data = JSON.parse(File.read(data_file), symbolize_names: true)

    @import = ImportForm.new
    preview_result = @import.preview_from_data(import_data)

    keep_current = params[:commit] == 'Оставить текущее'
    result = @import.import_from_data!(preview_result, keep_current: keep_current)

    File.delete(data_file) if File.exist?(data_file)

    if result[:success]
      render json: {
        success: true,
        message: "Импорт выполнен! Создано: #{result[:created_count]}, Обновлено: #{result[:updated_count]}, Оставлено без изменений: #{result[:kept_count]}, Всего: #{preview_result[:total]}"
      }
    else
      render json: {
        success: false,
        errors: result[:errors],
        created: result[:created_count],
        updated: result[:updated_count],
        kept: result[:kept_count],
        total: preview_result[:total]
      }
    end
  rescue => e
    Rails.logger.error "Confirm error: #{e.message}"
    render json: { success: false, errors: [e.message] }
  end

  private

  def save_uploaded_file(uploaded_file)
    temp_dir = Rails.root.join('tmp', 'imports')
    FileUtils.mkdir_p(temp_dir) unless Dir.exist?(temp_dir)
    
    filename = "upload_#{Time.current.to_i}_#{SecureRandom.hex(8)}.xlsx"
    temp_file = temp_dir.join(filename)
    
    File.open(temp_file, 'wb') { |f| f.write(uploaded_file.read) }
    temp_file.to_s
  end

  def save_import_data(data_id, data)
    temp_dir = Rails.root.join('tmp', 'imports')
    FileUtils.mkdir_p(temp_dir) unless Dir.exist?(temp_dir)
    
    temp_file = temp_dir.join("data_#{data_id}.json")
    File.write(temp_file, data.to_json)
    temp_file.to_s
  end

  def import_data_path(data_id)
    Rails.root.join('tmp', 'imports', "data_#{data_id}.json")
  end

  def cleanup_old_import_files
    temp_dir = Rails.root.join('tmp', 'imports')
    return unless Dir.exist?(temp_dir)
    
    Dir.glob(temp_dir.join('*')).each do |file|
      File.delete(file) if File.mtime(file) < 1.hour.ago rescue nil
    end
  end

  def import_params
    params.require(:import_form).permit(:file)
  end
end
