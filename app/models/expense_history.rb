class ExpenseHistory < ActiveRecord::Base
  belongs_to :issue
  belongs_to :material_stock
  belongs_to :user
  belongs_to :closer, class_name: 'User', foreign_key: 'closed_by'

  validates :quantity_used, numericality: { greater_than: 0 }
  validates :issue_id, uniqueness: { scope: :material_stock_id, message: 'уже списан для этой задачи' }

  scope :by_date, ->(start_date, end_date) { where(closed_at: start_date..end_date) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_material, ->(material_stock_id) { where(material_stock_id: material_stock_id) }

  def generate_pdf!
    self.class.generate_pdf_for_issue!(issue_id)
    reload
  end

  # Формирует один PDF-акт на задачу, включающий все её списанные материалы,
  # и проставляет путь к файлу всем связанным записям истории.
  def self.generate_pdf_for_issue!(issue_id)
    histories = where(issue_id: issue_id).includes(:material_stock, :user, :closer).order(:id)
    return nil if histories.empty?

    issue = Issue.find_by(id: issue_id)
    return nil unless issue

    last_history = histories.max_by(&:closed_at)

    html = ApplicationController.render(
      template: 'expense_pdf/act',
      layout: false,
      assigns: {
        issue: issue,
        histories: histories,
        accepted_by: issue.author,
        accepted_at: issue.created_on,
        issued_by: last_history&.user,
        issued_at: last_history&.closed_at
      }
    )

    pdf_data = WickedPdf.new.pdf_from_string(html, encoding: 'UTF-8')

    dir = Rails.root.join('files', 'redmine_expense')
    FileUtils.mkdir_p(dir)
    file_path = dir.join("act_issue_#{issue_id}.pdf")
    File.open(file_path, 'wb') { |f| f.write(pdf_data) }

    where(issue_id: issue_id).update_all(pdf_generated: true, pdf_file: file_path.to_s, updated_at: Time.current)

    file_path.to_s
  rescue => e
    Rails.logger.error "[redmine_expense] Ошибка генерации PDF для задачи ##{issue_id}: #{e.message}"
    nil
  end
end
