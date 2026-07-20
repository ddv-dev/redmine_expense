#!/bin/bash
# Тестовый скрипт: подписывает акт(ы) за период за всех членов комиссии, у
# кого запрошена подпись (requested: true, status: pending), КРОМЕ
# председателя — его подпись обязательна и всегда должна ставиться реально
# (председатель заходит и подписывает сам). Использует ту же логику
# (PeriodAct#sign!), что и кнопка "Подписать" в интерфейсе — акт при этом
# полностью подписанным не станет и PDF не сгенерируется, пока председатель
# не подпишет сам.
#
# Использование (запускать из любой директории, путь к Redmine — первым
# аргументом):
#   ./sign_period_act.sh /var/www/redmine          # подписать комиссию (без председателя) во ВСЕХ актах в статусе pending
#   ./sign_period_act.sh /var/www/redmine 42        # подписать комиссию (без председателя) только в акте #42
#
# Прим.: RAILS_ENV=production указывается ПЕРЕД командой (rails runner), а не
# после, как для rake — это разные соглашения, легко перепутать.

set -euo pipefail

REDMINE_ROOT="${1:?Укажите путь к Redmine, например: ./sign_period_act.sh /var/www/redmine [act_id]}"
ACT_ID="${2:-}"

cd "$REDMINE_ROOT"

ACT_ID="$ACT_ID" RAILS_ENV=production bundle exec rails runner - <<'RUBY'
act_id = ENV['ACT_ID'].to_s.strip
acts = act_id.empty? ? PeriodAct.where(status: 'pending') : PeriodAct.where(id: act_id, status: 'pending')

if acts.none?
  puts act_id.empty? ? 'Нет актов со статусом pending.' : "Акт ##{act_id} не найден или уже не в статусе pending."
  exit
end

acts.find_each do |act|
  puts "Акт ##{act.id} (проект ##{act.project_id}, период #{act.start_date}..#{act.end_date}):"

  signatures = act.period_act_signatures.where(requested: true, status: 'pending').includes(:user)
  signatures = signatures.where.not(user_id: act.chairman_id) if act.chairman_id.present?

  signatures.each do |signature|
    if signature.user.nil?
      puts "  пропущен: пользователь ##{signature.user_id} не найден"
      next
    end

    if act.sign!(signature.user)
      puts "  подписал: #{signature.user.name} (##{signature.user_id})"
    else
      puts "  НЕ УДАЛОСЬ подписать за #{signature.user.name} (##{signature.user_id})"
    end
  end

  act.reload
  status_line = "  итоговый статус акта: #{act.status}"
  status_line += " (осталось дождаться подписи председателя)" if act.pending? && act.chairman_id.present?
  status_line += ", PDF: #{act.pdf_file}" if act.pdf_file.present?
  puts status_line
end
RUBY
