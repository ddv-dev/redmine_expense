class ExpenseController < ApplicationController
  skip_before_action :check_if_login_required, only: [:materials, :brands, :models, :settings, :issue_materials, :stock_quantity]
  before_action :require_login, except: [:materials, :brands, :models, :settings, :issue_materials, :stock_quantity]
  
  def index
    @total_materials = MaterialStock.count
    @pending_expenses = IntermediateExpense.pending.count rescue 0
    @total_expenses = ExpenseHistory.count rescue 0
    @total_quantity = MaterialStock.sum(:quantity).to_i
    # Показываем ВСЕ материалы на главной, а не только 10
    @materials = MaterialStock.order(created_at: :desc).limit(50)
    
    render :index
  rescue => e
    render plain: "Ошибка: #{e.message}"
  end
  
  def materials
    types = MaterialStock.distinct.pluck(:material_type)
    render json: types.map { |t| { id: t, name: t } }
  end
  
  def brands
    material_type = params[:material_type]
    brands = MaterialStock.where(material_type: material_type).distinct.pluck(:brand)
    render json: brands.map { |b| { id: b, name: b } }
  end
  
  def models
    material_type = params[:material_type]
    brand = params[:brand]
    models = MaterialStock.where(material_type: material_type, brand: brand).distinct.pluck(:model)
    render json: models.map { |m| { id: m, name: m } }
  end
  
  def settings
    settings = Setting.plugin_redmine_expense
    status_in_progress = settings['status_in_progress']
    status_resolved = settings['status_resolved']
    
    if status_in_progress.is_a?(String)
      status_in_progress = [status_in_progress]
    elsif status_in_progress.nil?
      status_in_progress = []
    end
    
    if status_resolved.is_a?(String)
      status_resolved = [status_resolved]
    elsif status_resolved.nil?
      status_resolved = []
    end
    
    render json: { 
      status_in_progress: status_in_progress,
      status_resolved: status_resolved
    }
  rescue => e
    render json: { status_in_progress: [], status_resolved: [], error: e.message }
  end
  
  def issue_materials
    issue_id = params[:issue_id]
    materials = IntermediateExpense.where(issue_id: issue_id, status: 'pending')
                                   .includes(:material_stock)
    
    result = materials.map do |m|
      {
        material_type: m.material_stock.material_type,
        brand: m.material_stock.brand,
        model: m.material_stock.model,
        quantity: m.quantity_used,
        id: m.id
      }
    end
    
    render json: result
  rescue => e
    render json: { error: e.message, materials: [] }, status: 500
  end
  
  def stock_quantity
    material_type = params[:material_type]
    brand = params[:brand]
    model = params[:model]
    issue_id = params[:issue_id]
    
    stock = MaterialStock.find_by(
      material_type: material_type,
      brand: brand,
      model: model
    )
    
    if stock
      pending_query = IntermediateExpense
        .where(material_stock_id: stock.id, status: 'pending')
      
      if issue_id.present?
        pending_query = pending_query.where.not(issue_id: issue_id)
      end
      
      pending_quantity = pending_query.sum(:quantity_used)
      available_quantity = stock.quantity - pending_quantity
      
      if available_quantity < 0
        available_quantity = 0
      end
      
      render json: { 
        quantity: stock.quantity,
        pending_quantity: pending_quantity,
        available_quantity: available_quantity,
        available: available_quantity > 0,
        display_name: stock.display_name
      }
    else
      render json: { quantity: 0, available: false, error: 'Материал не найден' }, status: 404
    end
  end
  
  def save
    issue_id = params[:issue_id]
    materials_data = params[:materials]
    remove_ids = params[:remove_ids] || []
    
    if materials_data.is_a?(ActionController::Parameters)
      materials = materials_data.values
    elsif materials_data.is_a?(Hash)
      materials = materials_data.values
    elsif materials_data.is_a?(Array)
      materials = materials_data
    else
      materials = []
    end
    
    if remove_ids.present?
      IntermediateExpense.where(id: remove_ids, issue_id: issue_id).destroy_all
    end
    
    saved_count = 0
    errors = []
    
    if materials.present?
      materials.each do |material|
        mat_type = material[:material_type] || material['material_type']
        brand = material[:brand] || material['brand']
        model = material[:model] || material['model']
        quantity = material[:quantity] || material['quantity']
        mat_id = material[:id] || material['id']
        
        next if mat_type.blank? || quantity.blank?
        
        stock = MaterialStock.find_by(
          material_type: mat_type,
          brand: brand,
          model: model
        )
        
        if stock
          begin
            intermediate = nil
            
            if mat_id.present?
              intermediate = IntermediateExpense.find_by(id: mat_id, issue_id: issue_id)
            end
            
            if intermediate.nil?
              intermediate = IntermediateExpense.find_by(
                issue_id: issue_id,
                material_stock_id: stock.id,
                status: 'pending'
              )
            end
            
            if intermediate
              intermediate.update(
                quantity_used: quantity.to_f,
                user_id: User.current.id
              )
              saved_count += 1
            else
              IntermediateExpense.create(
                issue_id: issue_id,
                material_stock_id: stock.id,
                quantity_used: quantity.to_f,
                user_id: User.current.id,
                author_id: User.current.id,
                status: 'pending'
              )
              saved_count += 1
            end
          rescue => e
            errors << "#{stock.display_name}: #{e.message}"
          end
        else
          errors << "Материал '#{mat_type} #{brand} #{model}' не найден в базе"
        end
      end
      
      if errors.any?
        render json: { 
          success: false, 
          error: "Часть материалов не сохранена",
          details: errors,
          saved_count: saved_count
        }, status: 400
      else
        render json: { 
          success: true, 
          message: "Сохранено #{saved_count} материалов" 
        }
      end
    else
      render json: { success: true, message: 'Нет материалов для сохранения' }
    end
  rescue => e
    if e.message.include?('Duplicate entry')
      render json: { 
        success: false, 
        error: 'Этот материал уже добавлен в задачу. Если хотите изменить количество, отредактируйте существующую запись.',
        type: 'duplicate'
      }, status: 400
    else
      render json: { 
        success: false, 
        error: "Ошибка при сохранении: #{e.message}",
        type: 'unknown'
      }, status: 500
    end
  end
  
  def clear_stock
    if request.post?
      begin
        ActiveRecord::Base.transaction do
          IntermediateExpense.delete_all
          ExpenseHistory.delete_all
          MaterialStock.delete_all
        end
        
        flash[:notice] = "✅ Склад успешно очищен! Все материалы удалены."
        redirect_to expense_index_path
      rescue => e
        flash[:error] = "❌ Ошибка при очистке склада: #{e.message}"
        redirect_to expense_index_path
      end
    else
      render :clear_stock_confirm
    end
  end
end
