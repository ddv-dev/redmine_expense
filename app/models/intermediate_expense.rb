class IntermediateExpense < ActiveRecord::Base
  belongs_to :issue
  belongs_to :material_stock
  belongs_to :user
  belongs_to :author, class_name: 'User'
  belongs_to :approver, class_name: 'User', foreign_key: 'approved_by', optional: true

  validates :quantity_used, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[pending approved rejected] }

  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }

  # Не персистится в БД — флаг для UI, что списание прошло, но PDF не сформировался.
  attr_reader :pdf_generation_failed

  def pdf_generation_failed?
    !!@pdf_generation_failed
  end

  # Подтверждает списание: списывает остаток и создает запись в истории.
  # closed_by/closed_at позволяют автоматическому хуку смены статуса задачи
  # передать реального "закрывающего" пользователя и момент закрытия.
  def approve!(approver, closed_by: nil, closed_at: nil)
    return false unless pending?

    closed_by ||= approver
    closed_at ||= Time.current

    transaction do
      begin
        material_stock.deduct!(quantity_used)
      rescue ActiveRecord::RecordInvalid
        errors.add(:base, "Недостаточно материала «#{material_stock.display_name}» на складе (в наличии: #{material_stock.reload.quantity}, запрошено: #{quantity_used})")
        raise ActiveRecord::Rollback
      end

      update!(status: 'approved', approved_at: Time.current, approved_by: approver.id)

      ExpenseHistory.create!(
        issue_id: issue_id,
        material_stock_id: material_stock_id,
        quantity_used: quantity_used,
        user_id: user_id,
        closed_by: closed_by.id,
        closed_at: closed_at
      )
    end

    return false if errors.any?

    @pdf_generation_failed = ExpenseHistory.generate_pdf_for_issue!(issue_id).nil?

    true
  end

  def reject!
    return false unless pending?

    update!(status: 'rejected')
  end

  def pending?
    status == 'pending'
  end

  def approved?
    status == 'approved'
  end

  def rejected?
    status == 'rejected'
  end
end
