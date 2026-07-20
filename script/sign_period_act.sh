#!/bin/bash
# Тестовый скрипт: подписывает акт(ы) за период "за всех" — за каждого члена
# комиссии и за председателя, у кого запрошена подпись (requested: true,
# status: pending) — минуя необходимость реально заходить под каждым из них
# в Redmine. Использует ту же логику (PeriodAct#sign!), что и кнопка
# "Подписать" в интерфейсе, поэтому финальный PDF генерируется автоматически,
# как только подписан последний из запрошенных.
#
# Использование (запускать из любой директории, путь к Redmine — первым
# аргументом):
#   ./sign_period_act.sh /var/www/redmine          # подписать ВСЕ акты в статусе pending
#   ./sign_period_act.sh /var/www/redmine 42        # подписать только акт #42
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

  act.period_act_signatures.where(requested: true, status: 'pending').includes(:user).each do |signature|
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
  status_line += ", PDF: #{act.pdf_file}" if act.pdf_file.present?
  puts status_line
end
RUBY
