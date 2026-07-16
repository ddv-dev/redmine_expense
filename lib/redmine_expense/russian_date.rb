module RedmineExpense
  module RussianDate
    MONTHS_GENITIVE = %w[
      января февраля марта апреля мая июня
      июля августа сентября октября ноября декабря
    ].freeze

    module_function

    # "«29» января 2024 г." — формат даты для актов, как в исходном образце.
    def format(date)
      return '' unless date

      "«#{date.day}» #{MONTHS_GENITIVE[date.month - 1]} #{date.year} г."
    end

    # "17.07.2026" — вместо format_date/format_time из Redmine, которые
    # зависят от локали/настроек пользователя и на этом сервере отдают
    # американский формат MM/DD/YYYY. В актах и штампах подписи нужна только
    # дата, без времени, всегда в одном и том же формате.
    def short(date)
      return '' unless date

      date.strftime('%d.%m.%Y')
    end
  end
end
