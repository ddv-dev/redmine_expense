module ExpenseAuthorization
  extend ActiveSupport::Concern

  included do
    before_action :require_login
    helper_method :expense_authorized? if respond_to?(:helper_method)
  end

  # Разрешает доступ, если пользователь:
  # - администратор Redmine, либо
  # - имеет указанное право (через обычные роли/права модуля "Расход"), либо
  # - состоит в роли, назначенной как "Роль для доступа" в настройках плагина
  def require_expense_permission(permission)
    return true if expense_authorized?(permission)

    respond_to do |format|
      format.html { render_403 }
      format.json { render json: { success: false, error: 'Доступ запрещен' }, status: :forbidden }
      format.any { render_403 }
    end
    false
  end

  def expense_authorized?(permission)
    return true if User.current.admin?
    return true if User.current.allowed_to?(permission, nil, global: true)

    expense_role_id = Setting.plugin_redmine_expense['expense_role_id']
    return false if expense_role_id.blank?

    User.current.memberships.any? { |m| m.role_ids.map(&:to_s).include?(expense_role_id.to_s) }
  end
end
