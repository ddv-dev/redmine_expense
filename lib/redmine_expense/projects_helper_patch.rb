module RedmineExpense
  module ProjectsHelperPatch
    def self.included(base)
      base.class_eval do
        alias_method :project_settings_tabs_without_expense, :project_settings_tabs
        alias_method :project_settings_tabs, :project_settings_tabs_with_expense
      end
    end

    def project_settings_tabs_with_expense
      tabs = project_settings_tabs_without_expense

      # Вкладка видна только тем, кто реально может ее сохранить (то же
      # право, что проверяет ExpenseProjectSettingsController#update) —
      # иначе ее видел бы любой, кто может открыть страницу "Настройки"
      # проекта хоть по какому-то другому праву (например manage_categories).
      if @project.module_enabled?(:expense) &&
         (User.current.admin? || User.current.allowed_to?(:edit_project, @project))
        tabs << {
          name: 'expense',
          partial: 'expense_project_settings/tab',
          label: :label_expense
        }
      end

      tabs
    end
  end
end

ProjectsHelper.include(RedmineExpense::ProjectsHelperPatch) unless ProjectsHelper.included_modules.include?(RedmineExpense::ProjectsHelperPatch)
