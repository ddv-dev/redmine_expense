require 'redmine'

Redmine::Plugin.register :redmine_expense do
  name 'Redmine Expense plugin'
  author 'Demekhin Daniil'
  description 'Plugin for automatic write-off of consumables and inventory accounting'
  version '1.0.0'
  url ''
  author_url ''

  settings default: {
    'tracker_ids' => [],
    'status_in_progress' => [],
    'status_resolved' => [],
    'status_closed' => []
  }, partial: 'settings/expense_settings'

  # Включается/выключается для проекта на вкладке "Настройки" -> "Модули",
  # как любой другой модуль Redmine. Право require: :loggedin означает, что
  # оно не завязано на роли — доступ внутри включенного модуля дальше решает
  # RedmineExpense::Access (менеджеры/контрибьюторы, назначенные per-project
  # на вкладке "Расход" в настройках проекта), а не роли/права Redmine.
  project_module :expense do
    permission :view_expense, {
      expense: [:index, :materials, :brands, :models, :issue_materials, :stock_quantity, :save, :clear_stock, :clean_pdfs],
      stock: [:index, :edit, :update, :export],
      history: [:index, :show, :download_pdf],
      intermediate: [:index, :approve, :reject],
      import: [:new, :preview, :confirm]
    }, require: :loggedin
  end

  menu :project_menu, :expense, {
    controller: 'expense', action: 'index'
  }, caption: 'Расход', param: :project_id,
     if: Proc.new { |project| User.current.admin? || User.current.allowed_to?(:edit_project, project) }
end

require File.expand_path('issue_edit_hook', __dir__)
require_relative 'lib/redmine_expense/access'

# Хук для подключения JavaScript и CSS, и для добавления вкладки "Расход"
# на страницу настроек проекта.
# Redmine::Hook::ViewListener регистрирует свои подклассы автоматически при
# наследовании — явный Redmine::Hook.add_listener здесь был лишним и приводил
# к двойному подключению expense_fields.js/expense.css на каждой странице.
class ExpenseViewHook < Redmine::Hook::ViewListener
  def view_layouts_base_html_head(context)
    javascript_include_tag('expense_fields.js', plugin: 'redmine_expense') +
      stylesheet_link_tag('expense.css', plugin: 'redmine_expense')
  end

  def controller_projects_settings_before_render(context = {})
    project = context[:project]
    return unless project&.module_enabled?('expense')

    context[:tabs] << {
      name: 'expense',
      partial: 'redmine_expense/expense_project_settings/tab',
      label: :label_expense
    }
  end
end

# Автоматическое подтверждение списаний при переходе задачи в статус "Закрыта"
Rails.configuration.to_prepare do
  require_relative 'lib/redmine_expense/issue_patch'

  unless Issue.included_modules.include?(RedmineExpense::IssuePatch)
    Issue.include(RedmineExpense::IssuePatch)
  end
end
require File.expand_path('lib/redmine_expense/projects_helper_patch', __dir__)
