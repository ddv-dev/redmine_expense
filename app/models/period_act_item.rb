class PeriodActItem < ApplicationRecord
  belongs_to :period_act
  belongs_to :expense_history
end
