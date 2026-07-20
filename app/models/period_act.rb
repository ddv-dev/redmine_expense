class PeriodAct < ApplicationRecord
  belongs_to :project
  belongs_to :chairman, class_name: 'User', optional: true
  belongs_to :creator, class_name: 'User', foreign_key: 'created_by'
  has_many :period_act_items, dependent: :destroy
  has_many :expense_histories, through: :period_act_items
  has_many :period_act_signatures, dependent: :destroy

  validates :status, inclusion: { in: %w[pending signed] }
  validates :start_date, :end_date, presence: true

  def committee_id_list
    (committee_ids || '').split(',').map(&:strip).reject(&:blank?)
  end

  def committee_id_list=(ids)
    self.committee_ids = Array(ids).map(&:to_s).reject(&:blank?).join(',')
  end

  def requested_id_list
    (requested_ids || '').split(',').map(&:strip).reject(&:blank?)
  end

  def requested_id_list=(ids)
    self.requested_ids = Array(ids).map(&:to_s).reject(&:blank?).join(',')
  end

  def pending?
    status == 'pending'
  end

  def signed?
    status == 'signed'
  end

  # Список материалов для таблицы акта — сгруппировано и просуммировано по
  # полному "Наименованию номенклатуры" (как в исходном образце: поставщик/
  # модификация в акте не фигурируют, только наименование и количество).
  # Целые количества показываются без дробной части ("16", а не "16.0").
  def grouped_materials
    expense_histories.includes(:material_stock).group_by { |h| h.material_stock&.display_material_name.to_s }.map do |name, histories|
      { name: name, quantity: self.class.format_quantity(histories.sum(&:quantity_used)) }
    end.sort_by { |g| g[:name] }
  end

  def total_quantity
    self.class.format_quantity(expense_histories.sum(:quantity_used))
  end

  def self.format_quantity(quantity)
    RedmineExpense::Quantity.format(quantity)
  end

  def all_requested_signed?
    period_act_signatures.requested.where.not(status: 'signed').none?
  end

  def pdf_missing?
    pdf_file.blank? || !File.exist?(pdf_file)
  end

  # Фиксирует подпись пользователя, если у него есть ожидающая запрошенная
  # подпись на этом акте. Когда подписали все запрошенные — генерирует
  # финальный PDF и переводит акт в "Подписанные акты". Если генерация PDF
  # не удалась (см. лог сервера), акт остаётся в "pending" — иначе он попал
  # бы в "Подписанные акты" без самого PDF-файла. Повторить генерацию можно
  # кнопкой "Сформировать PDF" на странице акта.
  def sign!(user)
    signature = period_act_signatures.find_by(user_id: user.id, requested: true, status: 'pending')
    return false unless signature

    signature.update!(status: 'signed', signed_at: Time.current)

    if all_requested_signed?
      update!(status: 'signed') if generate_pdf!
    end

    true
  end

  def generate_pdf!
    render_locals = {
      act: self,
      project: project,
      grouped_materials: grouped_materials,
      chairman: chairman,
      signatures: period_act_signatures.includes(:user).order(:id)
    }

    html = ApplicationController.render(template: 'expense_pdf/period_act', layout: false, locals: render_locals)

    pdf_options = {
      encoding: 'UTF-8',
      # 3 см слева, 1.5 см справа, 2 см снизу — как в исходном образце.
      # Председатель и члены комиссии идут в обычном потоке документа сразу
      # после таблицы (по решению заказчика), никакой footer-области не нужно.
      margin: { top: 15, bottom: 20, left: 30, right: 15 }
    }
    exe_path = RedmineExpense::PdfGeneration.wkhtmltopdf_exe_path
    pdf_options[:exe_path] = exe_path if exe_path
    pdf_data = WickedPdf.new.pdf_from_string(html, **pdf_options)

    dir = Rails.root.join('files', 'redmine_expense')
    FileUtils.mkdir_p(dir)
    file_path = dir.join("period_act_#{id}.pdf")
    File.open(file_path, 'wb') { |f| f.write(pdf_data) }

    update_columns(pdf_file: file_path.to_s)

    file_path.to_s
  rescue => e
    Rails.logger.error "[redmine_expense] Ошибка генерации PDF периодического акта ##{id}: #{e.message}"
    nil
  end
end
