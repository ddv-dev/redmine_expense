module ExpenseAuthorization
  extend ActiveSupport::Concern

  included do
    before_action :require_login
    helper_method :expense_manager?, :expense_contributor? if respond_to?(:helper_method)
  end

  # Полный доступ к вкладке "Расход" (история, склад, промежуточная таблица,
  # импорт, подтверждение/отклонение списаний) — только пользователи, явно
  # назначенные в настройках плагина, либо администраторы.
  def require_expense_manager
    return true if expense_manager?

    respond_to do |format|
      format.html { render_403 }
      format.json { render json: { success: false, error: 'Доступ запрещен' }, status: :forbidden }
      format.any { render_403 }
    end
    false
  end

  # Доступ к добавлению расходных материалов в задачу.
  def require_expense_contributor
    return true if expense_contributor?

    respond_to do |format|
      format.html { render_403 }
      format.json { render json: { success: false, error: 'Доступ запрещен' }, status: :forbidden }
      format.any { render_403 }
    end
    false
  end

  def expense_manager?
    RedmineExpense::Access.manager?(User.current)
  end

  def expense_contributor?
    RedmineExpense::Access.contributor?(User.current)
  end
end
