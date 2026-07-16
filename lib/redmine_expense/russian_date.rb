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
  end
end
