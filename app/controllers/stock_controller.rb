require 'caxlsx'

class StockController < ApplicationController
  include ExpenseAuthorization

  before_action :require_expense_manager
  before_action :find_material, only: [:edit, :update]

  def index
    scope = MaterialStock.order(:material_type, :brand, :model)

    @total_items = MaterialStock.count
    @total_quantity = MaterialStock.sum(:quantity)
    @low_stock = MaterialStock.where('quantity < ?', MaterialStock::LOW_STOCK_THRESHOLD).count

    @material_count = @total_items
    @material_pages = Paginator.new @material_count, per_page_option, params['page']
    @materials = scope.offset(@material_pages.offset).limit(@material_pages.per_page)
  end

  def edit
    render json: material_json(@material)
  end

  def update
    if @material.update(material_params)
      respond_to do |format|
        format.json { render json: { success: true, material: material_json(@material) } }
        format.html { redirect_to stock_index_path, notice: 'Материал обновлен' }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, errors: @material.errors.full_messages }, status: :unprocessable_entity }
        format.html { redirect_to stock_index_path, alert: @material.errors.full_messages.join(', ') }
      end
    end
  end

  def export
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: 'Остатки') do |sheet|
      sheet.add_row ['Номенклатура', 'Наименование поставщика', 'Модификация', 'Количество', 'Описание']
      MaterialStock.order(:material_type, :brand, :model).find_each do |material|
        sheet.add_row [material.material_type, material.brand, material.model, material.quantity, material.description]
      end
    end

    send_data package.to_stream.read,
               filename: "stock_#{Date.current.strftime('%Y%m%d')}.xlsx",
               type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
               disposition: 'attachment'
  end

  private

  def find_material
    @material = MaterialStock.find(params[:id])
  end

  def material_params
    params.require(:material_stock).permit(:material_type, :brand, :model, :quantity, :description)
  end

  def material_json(material)
    {
      id: material.id,
      material_type: material.material_type,
      brand: material.brand,
      model: material.model,
      quantity: material.quantity,
      description: material.description
    }
  end
end
