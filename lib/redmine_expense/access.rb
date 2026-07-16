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

    # Комиссия по подписанию период-актов, плюс председатель — у него тоже
    # должен быть доступ к вкладкам "Подписание"/"Подписанные акты", хотя
    # сам он в системе ничего не подписывает.
    def committee_member?(user, project)
      return false unless user && project
      return true if manager?(user, project)

      setting = ExpenseProjectSetting.find_by(project_id: project.id)
      return false unless setting

      setting.committee_id_list.include?(user.id.to_s) || setting.chairman_id.to_s == user.id.to_s
    end
  end
end
