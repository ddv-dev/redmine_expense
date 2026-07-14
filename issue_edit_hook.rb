class IssueEditHook < Redmine::Hook::ViewListener
  render_on :view_issues_edit_form_bottom, :partial => "issues/expense_form"
end
