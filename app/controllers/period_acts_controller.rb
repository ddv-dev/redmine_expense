class PeriodActsController < ApplicationController
  include ExpenseAuthorization

  before_action :require_expense_manager, only: [:create, :clear]
  before_action :require_committee_access, only: [:index, :show, :signed, :sign, :download_pdf]
  before_action :find_act, only: [:show, :sign, :download_pdf]

  # Собирает акт по всем списаниям проекта за период, снэпшотит состав
  # комиссии/председателя из текущих настроек проекта и заводит по одной
  # ожидающей подписи на каждого члена комиссии (requested — только на тех,
  # кого отметили в форме "Отправить комиссии") плюс всегда одну на
  # председателя — он подписывает наравне с комиссией, его подпись нельзя
  # пропустить.
  def create
    start_date = parse_date(params[:start_date])
    end_date = parse_date(params[:end_date])

    if start_date.blank? || end_date.blank?
      flash[:error] = 'Укажите период (дата с / дата по) перед генерацией акта'
      redirect_to history_index_path(project_id: @project.id) and return
    end

    setting = ExpenseProjectSetting.for_project(@project)
    committee_ids = setting.committee_id_list

    if committee_ids.empty?
      flash[:error] = 'В проекте не настроена комиссия — добавьте её в настройках проекта на вкладке "Расход"'
      redirect_to history_index_path(project_id: @project.id) and return
    end

    requested_ids = Array(params[:signer_ids]).map(&:to_s) & committee_ids
    raw_skip_reasons = params[:skip_reasons]
    raw_skip_reasons = raw_skip_reasons.respond_to?(:to_unsafe_h) ? raw_skip_reasons.to_unsafe_h : (raw_skip_reasons || {})
    skip_reasons = raw_skip_reasons.transform_keys(&:to_s).transform_values { |v| v.to_s.strip }

    if requested_ids.empty?
      flash[:error] = 'Отметьте хотя бы одного члена комиссии, чья подпись запрашивается — иначе акт никто не сможет подписать'
      redirect_to history_index_path(project_id: @project.id) and return
    end

    histories = project_histories.where(closed_at: start_date.beginning_of_day..end_date.end_of_day)

    if histories.empty?
      flash[:error] = 'За выбранный период нет списаний — акт не создан'
      redirect_to history_index_path(project_id: @project.id) and return
    end

    act = nil
    ActiveRecord::Base.transaction do
      act = PeriodAct.new(
        project_id: @project.id,
        start_date: start_date,
        end_date: end_date,
        chairman_id: setting.chairman_id,
        created_by: User.current.id
      )
      act.committee_id_list = committee_ids
      act.requested_id_list = requested_ids
      act.save!

      histories.each { |h| PeriodActItem.create!(period_act: act, expense_history: h) }

      committee_ids.each do |uid|
        requested = requested_ids.include?(uid)
        PeriodActSignature.create!(
          period_act: act,
          user_id: uid,
          requested: requested,
          skip_reason: requested ? nil : skip_reasons[uid].presence
        )
      end

      # Председатель подписывает акт в системе наравне с членами комиссии —
      # его подпись всегда запрашивается (пропустить нельзя), даже если он
      # также значится в списке комиссии.
      if act.chairman_id.present?
        chairman_signature = act.period_act_signatures.find_by(user_id: act.chairman_id)
        if chairman_signature
          chairman_signature.update!(requested: true, skip_reason: nil) unless chairman_signature.requested?
        else
          PeriodActSignature.create!(period_act: act, user_id: act.chairman_id, requested: true)
        end
      end
    end

    flash[:notice] = 'Акт сформирован и отправлен на подписание комиссии'
    redirect_to period_acts_index_path(project_id: @project.id)
  end

  def index
    @acts = PeriodAct.where(project_id: @project.id, status: 'pending')
                      .includes(:creator, period_act_signatures: :user)
                      .order(created_at: :desc)
  end

  def show
    @signatures = @act.period_act_signatures.includes(:user).order(:id)
  end

  def sign
    if @act.signed?
      flash[:error] = 'Акт уже полностью подписан'
    elsif @act.sign!(User.current)
      flash[:notice] = @act.signed? ? 'Подпись зафиксирована, акт полностью подписан' : 'Подпись зафиксирована'
    else
      flash[:error] = 'Вы не можете подписать этот акт'
    end

    redirect_to period_acts_index_path(project_id: @project.id)
  end

  def signed
    @acts = PeriodAct.where(project_id: @project.id, status: 'signed').order(updated_at: :desc)
  end

  def download_pdf
    if @act.signed? && @act.pdf_file.present? && File.exist?(@act.pdf_file)
      send_file @act.pdf_file, type: 'application/pdf', disposition: 'inline', filename: "period_act_#{@act.id}.pdf"
    else
      flash[:error] = 'PDF доступен только для полностью подписанных актов'
      redirect_to signed_period_acts_path(project_id: @project.id)
    end
  end

  # Полная очистка подписанных актов проекта: удаляются и записи (вместе с
  # подписями/строками через dependent: :destroy), и PDF-файлы с диска.
  # Ожидающие подписания акты не трогаются.
  def clear
    acts = PeriodAct.where(project_id: @project.id, status: 'signed')
    deleted = 0

    acts.find_each do |act|
      if act.pdf_file.present? && File.exist?(act.pdf_file)
        begin
          File.delete(act.pdf_file)
        rescue => e
          Rails.logger.error "[redmine_expense] Не удалось удалить #{act.pdf_file}: #{e.message}"
        end
      end
      act.destroy
      deleted += 1
    end

    flash[:notice] = "Удалено подписанных актов: #{deleted}"
    redirect_to signed_period_acts_path(project_id: @project.id)
  end

  private

  def find_act
    @act = PeriodAct.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def project_histories
    ExpenseHistory.where(material_stock_id: MaterialStock.where(project_id: @project.id).select(:id))
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
