class PeriodActSignature < ApplicationRecord
  belongs_to :period_act
  belongs_to :user

  validates :status, inclusion: { in: %w[pending signed] }

  scope :requested, -> { where(requested: true) }
  scope :signed, -> { where(status: 'signed') }
  scope :pending, -> { where(status: 'pending') }
end
