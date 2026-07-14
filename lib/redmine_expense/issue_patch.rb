module RedmineExpense
  module IssuePatch
    extend ActiveSupport::Concern

    included do
      after_save :expense_process_status_change
    end

    private

    # Когда задача переходит в статус "Закрыта" (настраивается в настройках плагина),
    # автоматически подтверждает все ожидающие списания по этой задаче:
    # списывает остаток, создает записи в истории и генерирует PDF-акт.
    def expense_process_status_change
      return unless saved_change_to_status_id?

      settings = Setting.plugin_redmine_expense
      closed_status_ids = Array(settings['status_closed']).map(&:to_s)
      return if closed_status_ids.empty?
      return unless closed_status_ids.include?(status_id.to_s)

      pending = IntermediateExpense.where(issue_id: id, status: 'pending')
      return if pending.empty?

      closer = User.current
      pending.find_each do |intermediate|
        intermediate.approve!(closer, closed_by: closer, closed_at: Time.current)
      rescue => e
        Rails.logger.error "[redmine_expense] Не удалось автоматически подтвердить списание ##{intermediate.id} по задаче ##{id}: #{e.message}"
      end
    end
  end
end
