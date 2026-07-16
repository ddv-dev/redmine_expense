class IntermediateController < ApplicationController
  include ExpenseAuthorization

  before_action :require_expense_manager

  def index
    scope = project_intermediates.pending.includes(:material_stock, :user, :author).order(created_at: :desc)

    @intermediate_count = scope.count
    @intermediate_pages = Paginator.new @intermediate_count, per_page_option, params['page']
    @intermediates = scope.offset(@intermediate_pages.offset).limit(@intermediate_pages.per_page)
  end

  def approve
    @intermediate = project_intermediates.find(params[:id])

    if @intermediate.pending?
      closed_at = parse_closed_at(params[:closed_at]) || Time.current

      if @intermediate.approve!(User.current, closed_at: closed_at)
        if @intermediate.pdf_generation_failed?
          flash[:warning] = 'Списание подтверждено, но PDF-акт не удалось сформировать. Проверьте лог сервера (wkhtmltopdf) и повторно откройте карточку списания в истории — PDF попробует сформироваться заново при следующем скачивании.'
        else
          flash[:notice] = 'Списание подтверждено'
        end
      else
        flash[:error] = @intermediate.errors.full_messages.join(', ')
      end
    else
      flash[:error] = 'Запись уже обработана'
    end

    redirect_to intermediate_index_path(project_id: @project.id)
  end

  # Ручное добавление расходного материала в промежуточную таблицу — минуя
  # форму задачи, для случаев, когда контрибьютор забыл добавить материал
  # или у него нет доступа к самой задаче.
  def create
    issue = Issue.find_by(id: params[:issue_id])
    if issue.nil? || issue.project_id != @project.id
      flash[:error] = 'Задача не найдена в этом проекте'
      redirect_to intermediate_index_path(project_id: @project.id) and return
    end

    stock = MaterialStock.where(project_id: @project.id).where(material_type: params[:material_type]).order(:id).first
    if stock.nil?
      flash[:error] = 'Материал не найден на складе проекта'
      redirect_to intermediate_index_path(project_id: @project.id) and return
    end

    quantity = params[:quantity].to_f
    if quantity <= 0
      flash[:error] = 'Количество должно быть больше нуля'
      redirect_to intermediate_index_path(project_id: @project.id) and return
    end

    if quantity > stock.available_quantity
      flash[:error] = "Недостаточно материала «#{stock.display_name}» на складе (доступно: #{stock.available_quantity})"
      redirect_to intermediate_index_path(project_id: @project.id) and return
    end

    IntermediateExpense.create!(
      issue_id: issue.id,
      material_stock_id: stock.id,
      quantity_used: quantity,
      user_id: User.current.id,
      author_id: issue.author_id,
      status: 'pending'
    )

    flash[:notice] = 'Материал добавлен и ожидает подтверждения'
    redirect_to intermediate_index_path(project_id: @project.id)
  rescue => e
    flash[:error] = "Ошибка при добавлении материала: #{e.message}"
    redirect_to intermediate_index_path(project_id: @project.id)
  end

  def reject
    @intermediate = project_intermediates.find(params[:id])

    if @intermediate.pending?
      @intermediate.reject!
      flash[:notice] = 'Списание отклонено'
    else
      flash[:error] = 'Запись уже обработана'
    end

    redirect_to intermediate_index_path(project_id: @project.id)
  end

  private

  def project_intermediates
    IntermediateExpense.where(material_stock_id: MaterialStock.where(project_id: @project.id).select(:id))
  end

  def parse_closed_at(value)
    return nil if value.blank?
    Date.parse(value.to_s).to_time
  rescue ArgumentError, TypeError
    nil
  end
end
