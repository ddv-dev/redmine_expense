class StockController < ApplicationController
  before_action :require_login

  def index
    # Убираем limit, показываем все материалы
    @materials = MaterialStock
      .order(:material_type, :brand, :model)
      .page(params[:page])
      .per(25)
    
    @total_items = MaterialStock.count  # Считаем ВСЕ материалы
    @total_quantity = MaterialStock.sum(:quantity).to_i
    @low_stock = MaterialStock.where('quantity < 10').count
  end

  def edit
    @material = MaterialStock.find(params[:id])
  end

  def update
    @material = MaterialStock.find(params[:id])
    if @material.update(material_params)
      flash[:notice] = 'Материал обновлен'
      redirect_to stock_index_path
    else
      render :edit
    end
  end

  def export
    # TODO: Экспорт в Excel
    flash[:notice] = 'Экспорт будет реализован позже'
    redirect_to stock_index_path
  end

  private

  def material_params
    params.require(:material_stock).permit(:material_type, :brand, :model, :quantity, :description)
  end
end
