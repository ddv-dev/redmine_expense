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

  # Один акт — одна позиция: каждая запись истории получает собственный
  # PDF-файл с единственной строкой материала, даже если в задаче их
  # списано несколько разных.
  def generate_pdf!
    render_locals = {
      issue: issue,
      history: self,
      accepted_by: issue&.author,
      accepted_at: issue&.created_on,
      issued_by: user,
      issued_at: closed_at
    }

    html = ApplicationController.render(template: 'expense_pdf/act', layout: false, locals: render_locals)
    footer_html = ApplicationController.render(template: 'expense_pdf/act_footer', layout: false, locals: render_locals)

    pdf_options = {
      encoding: 'UTF-8',
      # Резервируем нижнее поле страницы под штампы подписи — это отдельная
      # область wkhtmltopdf (footer), а не просто отступ, поэтому основной
      # контент физически не может на нее наехать.
      margin: { top: 15, bottom: 50, left: 15, right: 15 },
      footer: { content: footer_html, spacing: 0 }
    }
    pdf_options[:exe_path] = self.class.wkhtmltopdf_exe_path if self.class.wkhtmltopdf_exe_path
    pdf_data = WickedPdf.new.pdf_from_string(html, **pdf_options)

    dir = Rails.root.join('files', 'redmine_expense')
    FileUtils.mkdir_p(dir)
    file_path = dir.join("act_history_#{id}.pdf")
    File.open(file_path, 'wb') { |f| f.write(pdf_data) }

    update_columns(pdf_generated: true, pdf_file: file_path.to_s)

    file_path.to_s
  rescue => e
    Rails.logger.error "[redmine_expense] Ошибка генерации PDF для списания ##{id}: #{e.message}"
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
