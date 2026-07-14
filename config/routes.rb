Rails.application.routes.draw do
  # Главная
  get '/expense', to: 'expense#index', as: 'expense_index'
  get '/expense/index', to: 'expense#index'

  # API для формы задачи
  get '/expense/materials', to: 'expense#materials'
  get '/expense/brands', to: 'expense#brands'
  get '/expense/models', to: 'expense#models'
  get '/expense/issue_materials', to: 'expense#issue_materials'
  get '/expense/stock_quantity', to: 'expense#stock_quantity'
  post '/expense/save', to: 'expense#save'

  # Очистка склада
  get '/expense/clear_stock', to: 'expense#clear_stock', as: 'clear_stock_expense'
  post '/expense/clear_stock', to: 'expense#clear_stock'

  # Склад
  get '/stock', to: 'stock#index', as: 'stock_index'
  get '/stock/export', to: 'stock#export', as: 'export_stock'
  get '/stock/:id/edit', to: 'stock#edit', as: 'edit_stock'
  patch '/stock/:id', to: 'stock#update', as: 'update_stock'

  # История
  get '/history', to: 'history#index', as: 'history_index'
  get '/history/:id', to: 'history#show', as: 'history_show'
  get '/history/:id/download_pdf', to: 'history#download_pdf', as: 'download_pdf_history'

  # Промежуточная таблица
  get '/intermediate', to: 'intermediate#index', as: 'intermediate_index'
  put '/intermediate/:id/approve', to: 'intermediate#approve', as: 'approve_intermediate'
  put '/intermediate/:id/reject', to: 'intermediate#reject', as: 'reject_intermediate'

  # Импорт
  get '/import/new', to: 'import#new', as: 'new_import'
  post '/import/preview', to: 'import#preview', as: 'preview_import'
  post '/import/confirm', to: 'import#confirm', as: 'confirm_import'
end
