require 'redmine'

Redmine::Plugin.register :redmine_expense do
  name 'Redmine Expense plugin'
  author 'Demekhin Daniil'
  description 'Plugin for automatic write-off of consumables and inventory accounting'
  version '1.0.0'
  url ''
  author_url ''

  settings default: {
    'project_ids' => [],
    'tracker_ids' => [],
    'status_in_progress' => [],
    'status_resolved' => [],
    'status_closed' => [],
    'expense_role_id' => nil
  }, partial: 'settings/expense_settings'

  project_module :expense do
    permission :view_expense_history, {
      history: [:index, :show, :download_pdf]
    }, require: :loggedin

    permission :view_expense_stock, {
      stock: [:index]
    }, require: :loggedin

    permission :manage_expense_stock, {
      stock: [:edit, :update, :export],
      import: [:new, :preview, :confirm]
    }, require: :loggedin

    permission :view_intermediate_expense, {
      intermediate: [:index]
    }, require: :loggedin

    permission :approve_expense, {
      intermediate: [:approve, :reject]
    }, require: :loggedin
  end

  menu :top_menu, :expense, {
    controller: 'expense', action: 'index'
  }, caption: 'Расход', if: Proc.new { User.current.logged? }
end

require File.expand_path('issue_edit_hook', __dir__)

# Хук для подключения JavaScript и CSS.
# Redmine::Hook::ViewListener регистрирует свои подклассы автоматически при
# наследовании — явный Redmine::Hook.add_listener здесь был лишним и приводил
# к двойному подключению expense_fields.js/expense.css на каждой странице.
class ExpenseViewHook < Redmine::Hook::ViewListener
  def view_layouts_base_html_head(context)
    javascript_include_tag('expense_fields.js', plugin: 'redmine_expense') +
      stylesheet_link_tag('expense.css', plugin: 'redmine_expense')
  end
end

# Автоматическое подтверждение списаний при переходе задачи в статус "Закрыта"
Rails.configuration.to_prepare do
  require_relative 'lib/redmine_expense/issue_patch'

  unless Issue.included_modules.include?(RedmineExpense::IssuePatch)
    Issue.include(RedmineExpense::IssuePatch)
  end
end
