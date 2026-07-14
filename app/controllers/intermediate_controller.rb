class IntermediateController < ApplicationController
  before_action :require_login

  def index
    @intermediates = IntermediateExpense
      .pending
      .includes(:material_stock, :user, :author)
      .order(created_at: :desc)
      .limit(50)
  end

  def approve
    @intermediate = IntermediateExpense.find(params[:id])
    
    if @intermediate.pending?
      begin
        @intermediate.approve!(User.current)
        flash[:notice] = 'Списание подтверждено'
      rescue => e
        flash[:error] = "Ошибка: #{e.message}"
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
