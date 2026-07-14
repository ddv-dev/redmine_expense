class HistoryController < ApplicationController
  before_action :require_login

  def index
    @histories = ExpenseHistory
      .includes(:material_stock, :user, :closer)
      .order(closed_at: :desc)
      .limit(50)
  end

  def show
    @history = ExpenseHistory.find(params[:id])
  end

  def download_pdf
    @history = ExpenseHistory.find(params[:id])
    flash[:notice] = 'PDF генерация будет реализована позже'
    redirect_to history_path(@history)
  end
end

  def download_pdf
    @history = ExpenseHistory.find(params[:id])
    if @history.pdf_file && File.exist?(@history.pdf_file)
      send_file @history.pdf_file, type: 'application/pdf', disposition: 'attachment'
    else
      flash[:error] = 'PDF файл не найден'
      redirect_to history_path(@history)
    end
  end
