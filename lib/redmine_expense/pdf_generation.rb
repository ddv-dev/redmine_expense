module RedmineExpense
  module PdfGeneration
    module_function

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
    def wkhtmltopdf_exe_path
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
end
