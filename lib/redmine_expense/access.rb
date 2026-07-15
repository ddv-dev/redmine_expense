module RedmineExpense
  module Access
    module_function

    def manager?(user, project)
      return false unless user && project
      return true if user.admin?

      setting = ExpenseProjectSetting.find_by(project_id: project.id)
      return false unless setting

      setting.manager_id_list.include?(user.id.to_s)
    end

    def contributor?(user, project)
      return false unless user && project
      return true if manager?(user, project)

      setting = ExpenseProjectSetting.find_by(project_id: project.id)
      return false unless setting

      setting.contributor_id_list.include?(user.id.to_s)
    end
  end
end
