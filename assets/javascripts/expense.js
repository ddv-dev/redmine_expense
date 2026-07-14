//= require jquery

$(document).ready(function() {
  // Добавление нового материала
  $('.add-expense-material').on('click', function(e) {
    e.preventDefault();
    var container = $('#expense-materials-container');
    var row = $('.expense-material-row:first').clone();
    
    // Очищаем значения
    row.find('select').val('');
    row.find('input[type="text"]').val('');
    row.find('.remove-expense-material').data('material-id', '');
    
    container.append(row);
  });
  
  // Удаление материала
  $(document).on('click', '.remove-expense-material', function(e) {
    e.preventDefault();
    var row = $(this).closest('.expense-material-row');
    var materialId = $(this).data('material-id');
    
    if (materialId) {
      // Если есть ID, помечаем на удаление
      row.append('<input type="hidden" name="expense[remove_ids][]" value="' + materialId + '">');
    }
    
    row.remove();
  });
});
