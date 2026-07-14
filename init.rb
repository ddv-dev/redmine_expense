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
      history: [:index, :show]
    }, require: :loggedin
    
    permission :manage_expense_stock, {
      stock: [:edit, :update]
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

# Хук для подключения JavaScript
class ExpenseViewHook < Redmine::Hook::ViewListener
  def view_layouts_base_html_head(context)
    javascript_include_tag 'expense_fields.js', plugin: 'redmine_expense'
  end
end

Redmine::Hook.add_listener(ExpenseViewHook)
