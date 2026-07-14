require 'digest'

class MaterialStock < ApplicationRecord
  self.table_name = 'material_stocks'

  has_many :intermediate_expenses, dependent: :restrict_with_error
  has_many :expense_histories, dependent: :restrict_with_error

  validates :material_type, presence: true, length: { maximum: 500 }
  validates :brand, presence: true, length: { maximum: 500 }
  validates :model, presence: true, length: { maximum: 500 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :hash_key, presence: true, uniqueness: true

  before_validation :generate_hash_key

  scope :low_stock, -> { where('quantity < ? AND quantity > ?', 10, 0) }

  LOW_STOCK_THRESHOLD = 10

  def generate_hash_key
    self.hash_key = self.class.build_hash_key(material_type, brand, model)
  end

  def self.build_hash_key(material_type, brand, model)
    Digest::MD5.hexdigest("#{material_type.to_s.strip.downcase}|#{brand.to_s.strip.downcase}|#{model.to_s.strip.downcase}")
  end

  def display_name
    "#{material_type} | #{brand} | #{model}"
  end

  def reserved_quantity(exclude_issue_id: nil)
    scope = IntermediateExpense.where(material_stock_id: id, status: 'pending')
    scope = scope.where.not(issue_id: exclude_issue_id) if exclude_issue_id.present?
    scope.sum(:quantity_used)
  end

  def available_quantity(exclude_issue_id: nil)
    quantity - reserved_quantity(exclude_issue_id: exclude_issue_id)
  end

  def sufficient_quantity?(requested_quantity)
    quantity.to_f >= requested_quantity.to_f
  end

  def deduct!(used_quantity)
    used_quantity = used_quantity.to_f

    with_lock do
      raise ActiveRecord::RecordInvalid.new(self) unless sufficient_quantity?(used_quantity)

      update!(quantity: quantity - used_quantity)
    end
  end

  def low_stock?
    quantity < LOW_STOCK_THRESHOLD
  end
end
