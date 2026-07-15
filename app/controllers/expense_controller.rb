class ExpenseController < ApplicationController
  include ExpenseAuthorization

  before_action :require_expense_contributor, only: [:materials, :brands, :models, :issue_materials, :stock_quantity, :save]
  before_action :find_issue, only: [:issue_materials, :stock_quantity, :save]

  def index
    return unless require_expense_manager

    @total_materials = project_materials.count
    @pending_expenses = project_intermediates.pending.count
    @total_expenses = project_histories.count
    @total_quantity = project_materials.sum(:quantity)
    @materials = project_materials.order(created_at: :desc).limit(10)
  end

  def materials
    types = project_materials.distinct.order(:material_type).pluck(:material_type)
    render json: types.map { |t| { id: t, name: t } }
  end

  def brands
    brands = project_materials.where(material_type: params[:material_type]).distinct.order(:brand).pluck(:brand)
    render json: brands.map { |b| { id: b, name: b } }
  end

  def models
    # id — реальный первичный ключ MaterialStock, а не текст модели.
    # Так дальнейшие запросы (остаток, сохранение) идут по ID, а не по
    # тройному текстовому совпадению, которое ломается на "грязных" данных
    # (лишние пробелы, обрезанные наименования и т.п.).
    models = project_materials.where(material_type: params[:material_type], brand: params[:brand])
                               .order(:model)
    render json: models.map { |m| { id: m.id, name: m.model } }
  end

  def issue_materials
    materials = IntermediateExpense.where(issue_id: @issue.id, status: 'pending').includes(:material_stock)

    result = materials.map do |m|
      {
        id: m.id,
        material_stock_id: m.material_stock_id,
        material_type: m.material_stock.material_type,
        brand: m.material_stock.brand,
        model: m.material_stock.model,
        quantity: m.quantity_used
      }
    end

    render json: result
  end

  def stock_quantity
    stock = find_material_stock(params[:material_stock_id], params[:material_type], params[:brand], params[:model])

    unless stock
      Rails.logger.warn "[redmine_expense] stock_quantity: материал не найден (material_stock_id=#{params[:material_stock_id].inspect}, material_type=#{params[:material_type].inspect}, brand=#{params[:brand].inspect}, model=#{params[:model].inspect})"
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
    unless User.current.allowed_to?(:edit_issues, @issue.project)
      Rails.logger.warn "[redmine_expense] save: доступ запрещен (user=#{User.current.id}/#{User.current.login}, issue=#{@issue.id}, project=#{@issue.project_id})"
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
      mat_stock_id = material[:material_stock_id] || material['material_stock_id']

      next if mat_type.blank? || quantity.blank?

      quantity_f = quantity.to_f
      if quantity_f <= 0
        errors << "Количество должно быть больше нуля для «#{mat_type} #{brand} #{model}»"
        next
      end

      stock = find_material_stock(mat_stock_id, mat_type, brand, model)
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
    return unless require_expense_manager

    if request.post?
      ActiveRecord::Base.transaction do
        project_intermediates.delete_all
        project_histories.delete_all
        project_materials.delete_all
      end

      flash[:notice] = 'Склад успешно очищен. Все материалы удалены.'
      redirect_to expense_index_path(project_id: @project.id)
    else
      @materials_count = project_materials.count
      @intermediates_count = project_intermediates.count
      @histories_count = project_histories.count
      render :clear_stock_confirm
    end
  rescue => e
    flash[:error] = "Ошибка при очистке склада: #{e.message}"
    redirect_to expense_index_path(project_id: @project.id)
  end

  # Удаляет только PDF-файлы актов, на которые больше не ссылается ни одна
  # запись ExpenseHistory (типичный случай — после "Очистить склад", где
  # история удаляется, а файлы актов на диске остаются). Файлы, на которые
  # всё ещё ссылается действующая запись, никогда не трогаются.
  def clean_pdfs
    return unless require_expense_manager

    @orphaned_files = orphaned_pdf_files
    @orphaned_size = @orphaned_files.sum { |f| File.size(f) rescue 0 }

    if request.post?
      deleted_count = 0

      @orphaned_files.each do |f|
        File.delete(f)
        deleted_count += 1
      rescue => e
        Rails.logger.error "[redmine_expense] Не удалось удалить #{f}: #{e.message}"
      end

      flash[:notice] = "Удалено осиротевших PDF-файлов: #{deleted_count}"
      redirect_to expense_index_path(project_id: @project.id)
    else
      render :clean_pdfs_confirm
    end
  rescue => e
    flash[:error] = "Ошибка при очистке PDF: #{e.message}"
    redirect_to expense_index_path(project_id: @project.id)
  end

  private

  # Все запросы к остаткам/промежуточной таблице/истории идут через
  # material_stock_id, отфильтрованный по проекту — у intermediate_expenses
  # и expense_histories своей колонки project_id нет, но материал, на
  # который они ссылаются, всегда принадлежит одному проекту.
  def project_materials
    MaterialStock.where(project_id: @project.id)
  end

  def project_intermediates
    IntermediateExpense.where(material_stock_id: project_materials.select(:id))
  end

  def project_histories
    ExpenseHistory.where(material_stock_id: project_materials.select(:id))
  end

  # PDF-файлы актов лежат в общем на диске каталоге (файл истории #42
  # не имеет отношения к проекту в своем имени), поэтому "осиротевший" файл
  # проверяется по ВСЕМ проектам сразу — иначе очистка из одного проекта
  # удалила бы файлы, все еще используемые записями истории другого проекта.
  def orphaned_pdf_files
    dir = Rails.root.join('files', 'redmine_expense')
    return [] unless Dir.exist?(dir)

    all_files = Dir.glob(dir.join('*.pdf')).map { |f| File.expand_path(f) }
    referenced = ExpenseHistory.where.not(pdf_file: [nil, '']).distinct.pluck(:pdf_file).map { |f| File.expand_path(f) }

    all_files - referenced
  end

  def find_issue
    @issue = Issue.find(params[:issue_id])

    unless @issue.project_id == @project.id && User.current.allowed_to?(:view_issues, @issue.project)
      Rails.logger.warn "[redmine_expense] find_issue: доступ запрещен (user=#{User.current.id}/#{User.current.login}, issue=#{@issue.id}, project=#{@issue.project_id})"
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

  # Ищет материал прежде всего по первичному ключу (надежно, не зависит от
  # текста), и только если его не передали — по тройке текстовых полей
  # (для обратной совместимости и запасного варианта). Всегда в пределах
  # текущего проекта, чтобы нельзя было списать материал чужого склада.
  def find_material_stock(material_stock_id, material_type, brand, model)
    if material_stock_id.present?
      stock = project_materials.find_by(id: material_stock_id)
      return stock if stock
    end

    project_materials.find_by(material_type: material_type, brand: brand, model: model)
  end
end
