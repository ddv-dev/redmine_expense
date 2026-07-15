class ExpenseProjectSetting < ApplicationRecord
  self.table_name = 'expense_project_settings'

  belongs_to :project

  def manager_id_list
    (manager_ids || '').split(',').map(&:strip).reject(&:blank?)
  end

  def manager_id_list=(ids)
    self.manager_ids = Array(ids).map(&:to_s).reject(&:blank?).join(',')
  end

  def contributor_id_list
    (contributor_ids || '').split(',').map(&:strip).reject(&:blank?)
  end

  def contributor_id_list=(ids)
    self.contributor_ids = Array(ids).map(&:to_s).reject(&:blank?).join(',')
  end

  def self.for_project(project)
    return new unless project
    find_by(project_id: project.id) || new(project_id: project.id)
  end
end
