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

  # Подтверждает все ожидающие списания проекта одной датой.
  def approve_all
    closed_at = parse_closed_at(params[:closed_at]) || Time.current
    pending = project_intermediates.pending.to_a

    if pending.empty?
      flash[:notice] = 'Нет списаний, ожидающих подтверждения'
      redirect_to intermediate_index_path(project_id: @project.id) and return
    end

    approved = 0
    pdf_failed = 0
    errors = []

    pending.each do |item|
      if item.approve!(User.current, closed_at: closed_at)
        approved += 1
        pdf_failed += 1 if item.pdf_generation_failed?
      else
        errors << item.errors.full_messages.join(', ')
      end
    rescue => e
      errors << e.message
    end

    messages = ["Подтверждено списаний: #{approved} из #{pending.size}"]
    messages << "PDF не сформирован для #{pdf_failed} (см. лог сервера)" if pdf_failed > 0

    if errors.any?
      flash[:error] = (messages + ["Ошибки: #{errors.uniq.join('; ')}"]).join('. ')
    elsif pdf_failed > 0
      flash[:warning] = messages.join('. ')
    else
      flash[:notice] = messages.join('. ')
    end

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
