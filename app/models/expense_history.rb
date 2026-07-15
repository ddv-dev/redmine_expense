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
      locals: {
        issue: issue,
        histories: histories,
        accepted_by: issue.author,
        accepted_at: issue.created_on,
        issued_by: last_history&.user,
        issued_at: last_history&.closed_at
      }
    )

    pdf_options = { encoding: 'UTF-8' }
    pdf_options[:exe_path] = wkhtmltopdf_exe_path if wkhtmltopdf_exe_path
    pdf_data = WickedPdf.new.pdf_from_string(html, **pdf_options)

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

  # wicked_pdf по умолчанию ищет бинарник по фиксированному пути
  # /usr/local/bin/wkhtmltopdf. Порядок поиска:
  # 1. Явно заданный путь через ENV['WKHTMLTOPDF_PATH'] или
  #    Setting.plugin_redmine_expense['wkhtmltopdf_path'] — на случай, если
  #    гем wkhtmltopdf-binary не поддерживает текущую ОС (его "бинарник" —
  #    это Ruby-скрипт, который сам проверяет версию ОС и отказывается
  #    запускаться, если под нее нет собранного пакета) и нужно указать
  #    системно установленный wkhtmltopdf вручную.
  # 2. Бинарник внутри самого гема wkhtmltopdf-binary.
  # 3. Что найдется в PATH.
  def self.wkhtmltopdf_exe_path
    return @wkhtmltopdf_exe_path if defined?(@wkhtmltopdf_exe_path)

    path = ENV['WKHTMLTOPDF_PATH'].presence
    path ||= Setting.plugin_redmine_expense['wkhtmltopdf_path'].presence

    if path.blank? && (spec = Gem.loaded_specs['wkhtmltopdf-binary'])
      path = Dir.glob(File.join(spec.gem_dir, '**', 'wkhtmltopdf')).find do |f|
        File.file?(f) && File.executable?(f)
      end
    end

    if path.blank?
      found = `which wkhtmltopdf 2>/dev/null`.strip
      path = found if found.present?
    end

    if path.blank?
      Rails.logger.error '[redmine_expense] Бинарник wkhtmltopdf не найден. Установите системный пакет (apt install wkhtmltopdf) ' \
                          'или укажите путь явно через переменную окружения WKHTMLTOPDF_PATH.'
    end

    @wkhtmltopdf_exe_path = path
  end
end
