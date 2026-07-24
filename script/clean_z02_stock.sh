#!/bin/bash
# Чистка уже загруженного склада от позиций, заведённых исключительно из
# партий с "з02" в коде партии (например, .з02.<>-ОМС-<>). Код партии в базе
# плагина не хранится, поэтому такие позиции определяются сверкой с ИСХОДНЫМ
# Excel-файлом (тем же, что импортировали): берутся ключи позиций
# (номенклатура+поставщик+модификация), встречающиеся в файле ТОЛЬКО в
# з02-партиях, и по этим ключам удаляются позиции склада данного проекта.
#
# По умолчанию — РЕЖИМ ПРОСМОТРА (ничего не удаляет, только показывает, что
# будет удалено). Для реального удаления добавьте APPLY=1.
#
# Позиции, по которым уже проходили списания (есть история или запись в
# промежуточной таблице), НЕ удаляются — они выводятся отдельно, решение по
# ним принимается вручную.
#
# Использование:
#   ./clean_z02_stock.sh /var/www/redmine <PROJECT_ID> /путь/к/файлу.xlsx           # просмотр
#   APPLY=1 ./clean_z02_stock.sh /var/www/redmine <PROJECT_ID> /путь/к/файлу.xlsx    # удаление
#
# Прим.: RAILS_ENV=production указывается ПЕРЕД командой (rails runner).

set -euo pipefail

REDMINE_ROOT="${1:?Использование: ./clean_z02_stock.sh <REDMINE_ROOT> <PROJECT_ID> <FILE.xlsx> (APPLY=1 для удаления)}"
PROJECT_ID="${2:?Укажите ID проекта вторым аргументом}"
FILE="${3:?Укажите путь к исходному Excel-файлу третьим аргументом}"
APPLY="${APPLY:-0}"

if [ ! -f "$FILE" ]; then
  echo "Файл не найден: $FILE" >&2
  exit 1
fi

cd "$REDMINE_ROOT"

PROJECT_ID="$PROJECT_ID" IMPORT_FILE="$FILE" APPLY="$APPLY" \
  RAILS_ENV=production bundle exec rails runner - <<'RUBY'
project_id = ENV['PROJECT_ID'].to_i
file_path  = ENV['IMPORT_FILE']
apply      = ENV['APPLY'] == '1'

project = Project.find_by(id: project_id)
abort "Проект ##{project_id} не найден" unless project

result = ImportForm.new.z02_only_hash_keys(file_path)
if result[:errors].any?
  abort "Ошибка разбора файла: #{result[:errors].join('; ')}"
end

pure_keys = result[:pure]
puts "Файл: #{file_path}"
puts "Проект: #{project.name} (##{project.id})"
puts "Позиций «чисто з02» в файле: #{pure_keys.size}"
puts "Режим: #{apply ? 'УДАЛЕНИЕ' : 'просмотр (ничего не удаляется)'}"
puts '-' * 60

stocks = MaterialStock.where(project_id: project.id, hash_key: pure_keys)
puts "Найдено таких позиций на складе проекта: #{stocks.count}"
puts

deleted = 0
skipped_refs = 0
failed = 0

stocks.find_each do |stock|
  used = stock.expense_histories.count
  pending = stock.intermediate_expenses.count
  label = "[#{stock.id}] #{stock.display_name} (кол-во: #{stock.quantity})"

  if used > 0 || pending > 0
    puts "ПРОПУЩЕНО (есть списания/резерв: история=#{used}, промеж.=#{pending}): #{label}"
    skipped_refs += 1
    next
  end

  if apply
    if stock.destroy
      puts "УДАЛЕНО: #{label}"
      deleted += 1
    else
      puts "НЕ УДАЛОСЬ (#{stock.errors.full_messages.join(', ')}): #{label}"
      failed += 1
    end
  else
    puts "будет удалено: #{label}"
    deleted += 1
  end
end

puts
puts '-' * 60
if apply
  puts "Удалено: #{deleted}; пропущено из-за списаний: #{skipped_refs}; ошибок: #{failed}"
else
  puts "Будет удалено: #{deleted}; пропущено из-за списаний: #{skipped_refs}"
  puts "Для реального удаления запустите ту же команду с APPLY=1 в начале."
end
RUBY
