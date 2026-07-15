class HistoryController < ApplicationController
  include ExpenseAuthorization

  before_action { require_expense_permission(:view_expense_history) }

  def index
    scope = ExpenseHistory.includes(:material_stock, :user, :closer).order(closed_at: :desc)
    scope = apply_filters(scope)

    @filter_user_id = params[:user_id]
    @filter_material_stock_id = params[:material_stock_id]
    @filter_start_date = params[:start_date]
    @filter_end_date = params[:end_date]

    @users = User.where(id: ExpenseHistory.distinct.pluck(:user_id)).order(:lastname, :firstname)
    @material_stocks = MaterialStock.where(id: ExpenseHistory.distinct.pluck(:material_stock_id))
                                     .order(:material_type, :brand, :model)

    @history_count = scope.count
    @history_pages = Paginator.new @history_count, per_page_option, params['page']
    @histories = scope.offset(@history_pages.offset).limit(@history_pages.per_page)
  end

  def show
    @history = ExpenseHistory.includes(:material_stock, :user, :closer).find(params[:id])
  end

  def download_pdf
    @history = ExpenseHistory.find(params[:id])

    if @history.pdf_file.blank? || !File.exist?(@history.pdf_file)
      ExpenseHistory.generate_pdf_for_issue!(@history.issue_id)
      @history.reload
    end

    if @history.pdf_file.present? && File.exist?(@history.pdf_file)
      send_file @history.pdf_file, type: 'application/pdf', disposition: 'inline',
                filename: "act_issue_#{@history.issue_id}.pdf"
    else
      flash[:error] = 'PDF файл не найден'
      redirect_to history_show_path(@history)
    end
  end

  private

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
