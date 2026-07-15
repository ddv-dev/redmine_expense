class IssueEditHook < Redmine::Hook::ViewListener
  # view_issues_edit_form_bottom не существует в Redmine 6 — реальный хук,
  # рендерящийся в app/views/issues/_form.html.erb (общий для создания и
  # редактирования задачи), называется view_issues_form_details_bottom.
  render_on :view_issues_form_details_bottom, :partial => "issues/expense_form"
end
