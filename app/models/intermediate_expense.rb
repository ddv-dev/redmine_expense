class IntermediateExpense < ActiveRecord::Base
  belongs_to :issue
  belongs_to :material_stock
  belongs_to :user
  belongs_to :author, class_name: 'User'
  
  validates :quantity_used, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[pending approved rejected] }
  
  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  
  def approve!(approver)
    return unless pending?
    
    transaction do
      if material_stock.sufficient_quantity?(quantity_used)
        material_stock.deduct!(quantity_used)
        update!(status: 'approved', approved_at: Time.current, approved_by: approver.id)
      else
        errors.add(:base, 'Insufficient stock')
        raise ActiveRecord::RecordInvalid, self
      end
    end
  end

  def reject!
    update!(status: 'rejected') if pending?
  end

  def pending?
    status == 'pending'
  end

  def approved?
    status == 'approved'
  end
end
