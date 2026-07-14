class StockController < ApplicationController
  before_action :require_login
  
  def index
    @materials = MaterialStock.order(:material_type, :brand, :model)
    
    # Статистика
    @total_items = @materials.count
    @total_quantity = @materials.sum(:quantity)
    @low_stock = @materials.where('quantity < ?', 10).count
    
    # Временное решение без пагинации
    @materials = @materials.limit(100) # Просто ограничим количество
    
    respond_to do |format|
      format.html
    end
  rescue => e
    flash[:error] = "Ошибка: #{e.message}"
    redirect_to expense_path
  end
end