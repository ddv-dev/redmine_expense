class AddSkipReasonToPeriodActSignatures < ActiveRecord::Migration[7.2]
  def change
    add_column :period_act_signatures, :skip_reason, :string
  end
end
