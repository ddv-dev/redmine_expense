module ExpenseAuthorization
  extend ActiveSupport::Concern

  included do
    before_action :require_login
    before_action :find_expense_project
    helper_method :expense_manager?, :expense_contributor? if respond_to?(:helper_method)
  end

  # Полный доступ к вкладке "Расход" в рамках текущего проекта (история,
  # склад, промежуточная таблица, импорт, подтверждение/отклонение
  # списаний) — только пользователи, назначенные менеджерами этого проекта
  # на вкладке "Расход" в настройках проекта, либо администраторы.
  def require_expense_manager
    return true if expense_manager?

    render_expense_forbidden
    false
  end

  # Доступ к добавлению расходных материалов в задачу в рамках проекта.
  def require_expense_contributor
    return true if expense_contributor?

    render_expense_forbidden
    false
  end

  def expense_manager?
    RedmineExpense::Access.manager?(User.current, @project)
  end

  def expense_contributor?
    RedmineExpense::Access.contributor?(User.current, @project)
  end

  private

  def find_expense_project
    @project = Project.find(params[:project_id])
    render_expense_forbidden unless @project.module_enabled?('expense')
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def render_expense_forbidden
    respond_to do |format|
      format.html { render_403 }
      format.json { render json: { success: false, error: 'Доступ запрещен' }, status: :forbidden }
      format.any { render_403 }
    end
  end
end
