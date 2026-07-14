class ExpenseController < ApplicationController
  include ExpenseAuthorization

  before_action :find_issue, only: [:issue_materials, :stock_quantity, :save]

  def index
    @total_materials = MaterialStock.count
    @pending_expenses = IntermediateExpense.pending.count
    @total_expenses = ExpenseHistory.count
    @total_quantity = MaterialStock.sum(:quantity)
    @materials = MaterialStock.order(created_at: :desc).limit(10)
  end

  def materials
    types = MaterialStock.distinct.order(:material_type).pluck(:material_type)
    render json: types.map { |t| { id: t, name: t } }
  end

  def brands
    brands = MaterialStock.where(material_type: params[:material_type]).distinct.order(:brand).pluck(:brand)
    render json: brands.map { |b| { id: b, name: b } }
  end

  def models
    models = MaterialStock.where(material_type: params[:material_type], brand: params[:brand])
                           .distinct.order(:model).pluck(:model)
    render json: models.map { |m| { id: m, name: m } }
  end

  def issue_materials
    materials = IntermediateExpense.where(issue_id: @issue.id, status: 'pending').includes(:material_stock)

    result = materials.map do |m|
      {
        id: m.id,
        material_type: m.material_stock.material_type,
        brand: m.material_stock.brand,
        model: m.material_stock.model,
        quantity: m.quantity_used
      }
    end

    render json: result
  end

  def stock_quantity
    stock = MaterialStock.find_by(
      material_type: params[:material_type],
      brand: params[:brand],
      model: params[:model]
    )

    unless stock
      render json: { quantity: 0, available: false, error: 'Материал не найден' }, status: :not_found
      return
    end

    available_quantity = stock.available_quantity(exclude_issue_id: @issue.id)
    pending_quantity = stock.reserved_quantity(exclude_issue_id: @issue.id)

    render json: {
      quantity: stock.quantity,
      pending_quantity: pending_quantity,
      available_quantity: [available_quantity, 0].max,
      available: available_quantity > 0,
      display_name: stock.display_name
    }
  end

  def save
    unless User.current.allowed_to?(:edit_issue, @issue.project)
      render json: { success: false, error: 'Доступ запрещен' }, status: :forbidden
      return
    end

    remove_ids = Array(params[:remove_ids]).reject(&:blank?)
    if remove_ids.present?
      IntermediateExpense.where(id: remove_ids, issue_id: @issue.id, status: 'pending').destroy_all
    end

    materials = extract_materials_param(params[:materials])
    saved_count = 0
    errors = []

    materials.each do |material|
      mat_type = material[:material_type] || material['material_type']
      brand = material[:brand] || material['brand']
      model = material[:model] || material['model']
      quantity = material[:quantity] || material['quantity']
      mat_id = material[:id] || material['id']

      next if mat_type.blank? || quantity.blank?

      quantity_f = quantity.to_f
      if quantity_f <= 0
        errors << "Количество должно быть больше нуля для «#{mat_type} #{brand} #{model}»"
        next
      end

      stock = MaterialStock.find_by(material_type: mat_type, brand: brand, model: model)
      unless stock
        errors << "Материал «#{mat_type} #{brand} #{model}» не найден в базе"
        next
      end

      if quantity_f > stock.available_quantity(exclude_issue_id: @issue.id)
        errors << "Недостаточно материала «#{stock.display_name}» на складе"
        next
      end

      begin
        intermediate = mat_id.present? ? IntermediateExpense.find_by(id: mat_id, issue_id: @issue.id) : nil
        intermediate ||= IntermediateExpense.find_by(issue_id: @issue.id, material_stock_id: stock.id, status: 'pending')

        if intermediate
          intermediate.update!(quantity_used: quantity_f, user_id: User.current.id)
        else
          IntermediateExpense.create!(
            issue_id: @issue.id,
            material_stock_id: stock.id,
            quantity_used: quantity_f,
            user_id: User.current.id,
            author_id: @issue.author_id,
            status: 'pending'
          )
        end
        saved_count += 1
      rescue => e
        errors << "#{stock.display_name}: #{e.message}"
      end
    end

    if errors.any?
      render json: { success: false, error: 'Часть материалов не сохранена', details: errors, saved_count: saved_count }, status: :unprocessable_entity
    else
      render json: { success: true, message: "Сохранено #{saved_count} материалов" }
    end
  end

  def clear_stock
    return unless require_expense_permission(:manage_expense_stock)

    if request.post?
      ActiveRecord::Base.transaction do
        IntermediateExpense.delete_all
        ExpenseHistory.delete_all
        MaterialStock.delete_all
      end

      flash[:notice] = 'Склад успешно очищен. Все материалы удалены.'
      redirect_to expense_index_path
    else
      render :clear_stock_confirm
    end
  rescue => e
    flash[:error] = "Ошибка при очистке склада: #{e.message}"
    redirect_to expense_index_path
  end

  private

  def find_issue
    @issue = Issue.find(params[:issue_id])

    unless User.current.allowed_to?(:view_issues, @issue.project)
      render json: { success: false, error: 'Доступ запрещен' }, status: :forbidden
    end
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Задача не найдена' }, status: :not_found
  end

  def extract_materials_param(materials_data)
    case materials_data
    when ActionController::Parameters, Hash
      materials_data.values
    when Array
      materials_data
    else
      []
    end
  end
end
