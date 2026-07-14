class IntermediateController < ApplicationController
  include ExpenseAuthorization

  before_action(only: [:index]) { require_expense_permission(:view_intermediate_expense) }
  before_action(only: [:approve, :reject]) { require_expense_permission(:approve_expense) }

  PER_PAGE = 25

  def index
    scope = IntermediateExpense.pending.includes(:material_stock, :user, :author).order(created_at: :desc)

    @intermediate_count = scope.count
    @intermediate_pages = Paginator.new @intermediate_count, PER_PAGE, params['page']
    @intermediates = scope.offset(@intermediate_pages.offset).limit(@intermediate_pages.per_page)
  end

  def approve
    @intermediate = IntermediateExpense.find(params[:id])

    if @intermediate.pending?
      if @intermediate.approve!(User.current)
        flash[:notice] = 'Списание подтверждено'
      else
        flash[:error] = @intermediate.errors.full_messages.join(', ')
      end
    else
      flash[:error] = 'Запись уже обработана'
    end

    redirect_to intermediate_index_path
  end

  def reject
    @intermediate = IntermediateExpense.find(params[:id])

    if @intermediate.pending?
      @intermediate.reject!
      flash[:notice] = 'Списание отклонено'
    else
      flash[:error] = 'Запись уже обработана'
    end

    redirect_to intermediate_index_path
  end
end
