require 'combine_pdf'

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

  # Объединяет PDF-акты (Заказ-наряды) всех списаний проекта за период в
  # один файл: одно списание — одна страница (или больше, если акт сам
  # многостраничный). Отсутствующие PDF генерируются на лету.
  def export_pdf
    start_date = parse_date(params[:start_date])
    end_date = parse_date(params[:end_date])

    if start_date.nil? || end_date.nil?
      flash[:error] = 'Укажите период (дата с / дата по) для выгрузки PDF'
      redirect_to history_index_path(project_id: @project.id) and return
    end

    histories = ExpenseHistory.joins(:material_stock)
                               .where(material_stocks: { project_id: @project.id })
                               .where(closed_at: start_date.beginning_of_day..end_date.end_of_day)
                               .order(:closed_at)

    if histories.empty?
      flash[:error] = 'За выбранный период нет списаний'
      redirect_to history_index_path(project_id: @project.id) and return
    end

    combined = CombinePDF.new
    failed = 0

    histories.each do |history|
      path = history.pdf_file.presence
      path = nil if path && !File.exist?(path)
      path ||= history.generate_pdf!

      if path && File.exist?(path)
        combined << CombinePDF.load(path)
      else
        failed += 1
      end
    rescue => e
      Rails.logger.error "[redmine_expense] export_pdf: не удалось включить акт списания ##{history.id}: #{e.message}"
      failed += 1
    end

    if combined.pages.empty?
      flash[:error] = 'Не удалось сформировать ни одного PDF-акта за период (см. лог сервера)'
      redirect_to history_index_path(project_id: @project.id) and return
    end

    flash[:warning] = "Не удалось включить в файл актов: #{failed}" if failed > 0

    send_data combined.to_pdf,
              filename: "acts_#{start_date.strftime('%Y%m%d')}-#{end_date.strftime('%Y%m%d')}.pdf",
              type: 'application/pdf',
              disposition: 'attachment'
  end

  private

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

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
