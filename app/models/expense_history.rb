class ExpenseHistory < ActiveRecord::Base
  belongs_to :issue
  belongs_to :material_stock
  belongs_to :user
  belongs_to :closer, class_name: 'User', foreign_key: 'closed_by'
  
  validates :quantity_used, numericality: { greater_than: 0 }
  
  scope :by_date, ->(start_date, end_date) { where(closed_at: start_date..end_date) }
  
  def generate_pdf!
    # Будет реализовано позже
    update!(pdf_generated: true)
  end
end
