class HistoryController < ApplicationController
  include ExpenseAuthorization

  before_action :require_expense_manager

  def index
    project_scope = ExpenseHistory.joins(:material_stock).where(material_stocks: { project_id: @project.id })
    scope = project_scope.includes(:material_stock, :user, :closer).order(closed_at: :desc)
    scope = apply_filters(scope)

    @filter_user_id = params[:user_id]
    @filter_material_stock_id = params[:material_stock_id]
    @filter_start_date = params[:start_date]
    @filter_end_date = params[:end_date]

    @users = User.where(id: project_scope.distinct.pluck(:user_id)).order(:lastname, :firstname)
    @material_stocks = MaterialStock.where(project_id: @project.id)
                                     .order(:material_type, :brand, :model)

    @history_count = scope.count
    @history_pages = Paginator.new @history_count, per_page_option, params['page']
    @histories = scope.offset(@history_pages.offset).limit(@history_pages.per_page)
  end

  def show
    @history = find_project_history(params[:id])
  end

  def download_pdf
    @history = find_project_history(params[:id])

    if @history.pdf_file.blank? || !File.exist?(@history.pdf_file)
      @history.generate_pdf!
    end

    if @history.pdf_file.present? && File.exist?(@history.pdf_file)
      send_file @history.pdf_file, type: 'application/pdf', disposition: 'inline',
                filename: "act_#{@history.id}.pdf"
    else
      flash[:error] = 'PDF файл не найден'
      redirect_to history_show_path(id: @history.id, project_id: @project.id)
    end
  end

  private

  def find_project_history(id)
    ExpenseHistory.joins(:material_stock).where(material_stocks: { project_id: @project.id })
                   .includes(:material_stock, :user, :closer).find(id)
  end

  def apply_filters(scope)
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.where(material_stock_id: params[:material_stock_id]) if params[:material_stock_id].present?

    if params[:start_date].present?
      scope = scope.where('closed_at >= ?', Date.parse(params[:start_date]).beginning_of_day)
    end

    if params[:end_date].present?
      scope = scope.where('closed_at <= ?', Date.parse(params[:end_date]).end_of_day)
    end

    scope
  rescue ArgumentError
    scope
  end
end
