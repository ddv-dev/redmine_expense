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
      if @intermediate.approve!(User.current)
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
end
