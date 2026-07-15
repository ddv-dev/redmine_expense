class ExpenseProjectSettingsController < ApplicationController
  before_action :find_project
  before_action :authorize_project_admin

  def update
    setting = ExpenseProjectSetting.for_project(@project)
    setting.manager_id_list = params[:manager_ids]
    setting.contributor_id_list = params[:contributor_ids]

    if setting.save
      flash[:notice] = 'Настройки доступа к "Расход" сохранены'
    else
      flash[:error] = setting.errors.full_messages.join(', ')
    end

    redirect_to settings_project_path(@project, tab: 'expense')
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_project_admin
    render_403 unless User.current.allowed_to?(:edit_project, @project)
  end
end
