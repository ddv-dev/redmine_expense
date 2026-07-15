module RedmineExpense
  module Access
    module_function

    def manager?(user = User.current)
      return true if user.admin?
      ids('expense_manager_ids').include?(user.id.to_s)
    end

    def contributor?(user = User.current)
      return true if manager?(user)
      ids('expense_contributor_ids').include?(user.id.to_s)
    end

    def ids(key)
      Array(Setting.plugin_redmine_expense[key]).map(&:to_s)
    end
  end
end
