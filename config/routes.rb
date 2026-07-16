Rails.application.routes.draw do
  scope '/projects/:project_id' do
    # Главная
    get '/expense', to: 'expense#index', as: 'expense_index'
    get '/expense/index', to: 'expense#index'

    # API для формы задачи
    get '/expense/materials', to: 'expense#materials'
    get '/expense/resolve_stock', to: 'expense#resolve_stock'
    get '/expense/issue_materials', to: 'expense#issue_materials'
    get '/expense/stock_quantity', to: 'expense#stock_quantity'
    post '/expense/save', to: 'expense#save'

    # Очистка склада
    get '/expense/clear_stock', to: 'expense#clear_stock', as: 'clear_stock_expense'
    post '/expense/clear_stock', to: 'expense#clear_stock'

    # Очистка осиротевших PDF-файлов актов
    get '/expense/clean_pdfs', to: 'expense#clean_pdfs', as: 'clean_pdfs_expense'
    post '/expense/clean_pdfs', to: 'expense#clean_pdfs'

    # Склад
    get '/stock', to: 'stock#index', as: 'stock_index'
    get '/stock/export', to: 'stock#export', as: 'export_stock'
    post '/stock', to: 'stock#create', as: 'create_stock'
    get '/stock/:id/edit', to: 'stock#edit', as: 'edit_stock'
    patch '/stock/:id', to: 'stock#update', as: 'update_stock'

    # История
    get '/history', to: 'history#index', as: 'history_index'
    get '/history/:id', to: 'history#show', as: 'history_show'
    get '/history/:id/download_pdf', to: 'history#download_pdf', as: 'download_pdf_history'
    post '/history/generate_act', to: 'period_acts#create', as: 'generate_period_act'

    # Период-акты (подписание комиссией)
    get '/period_acts', to: 'period_acts#index', as: 'period_acts_index'
    get '/period_acts/signed', to: 'period_acts#signed', as: 'signed_period_acts'
    get '/period_acts/:id', to: 'period_acts#show', as: 'period_act_show'
    put '/period_acts/:id/sign', to: 'period_acts#sign', as: 'sign_period_act'
    get '/period_acts/:id/download_pdf', to: 'period_acts#download_pdf', as: 'download_pdf_period_act'

    # Промежуточная таблица
    get '/intermediate', to: 'intermediate#index', as: 'intermediate_index'
    put '/intermediate/:id/approve', to: 'intermediate#approve', as: 'approve_intermediate'
    put '/intermediate/:id/reject', to: 'intermediate#reject', as: 'reject_intermediate'

    # Импорт
    get '/import/new', to: 'import#new', as: 'new_import'
    post '/import/preview', to: 'import#preview', as: 'preview_import'
    post '/import/confirm', to: 'import#confirm', as: 'confirm_import'

    # Настройки доступа плагина в рамках проекта (вкладка в Настройках проекта)
    patch '/expense_settings', to: 'expense_project_settings#update', as: 'update_expense_project_settings'
  end
end
