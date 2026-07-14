$(document).ready(function() {
  console.log("Expense plugin loaded!");
  
  if ($('#issue-form').length === 0) return;
  
  var issueId = $('#issue-form').find('input[name="id"]').val() || 
                window.location.pathname.match(/\/issues\/(\d+)/)?.[1];
  
  $.ajax({
    url: '/expense/settings',
    method: 'GET',
    dataType: 'json',
    success: function(settings) {
      window.expenseSettings = settings;
      console.log("Expense settings loaded:", settings);
      initExpenseFields(issueId);
    },
    error: function() {
      console.log("Error loading settings, using defaults");
      window.expenseSettings = { status_in_progress: [], status_resolved: [] };
      initExpenseFields(issueId);
    }
  });
  
  function initExpenseFields(issueId) {
    var statusInProgress = window.expenseSettings.status_in_progress || [];
    var statusResolved = window.expenseSettings.status_resolved || [];
    var allStatuses = statusInProgress.concat(statusResolved);
    var statusId = $('#issue_status_id').val();
    
    if (allStatuses.length > 0 && allStatuses.includes(statusId)) {
      loadSavedMaterials(issueId);
    }
    
    $('#issue_status_id').on('change', function() {
      var newStatus = $(this).val();
      if (allStatuses.includes(newStatus)) {
        if ($('#expense-fields-container').length === 0) {
          loadSavedMaterials(issueId);
        }
      } else {
        $('#expense-fields-container').remove();
      }
    });
    
    $('#issue-form').on('submit', function(e) {
      e.preventDefault();
      console.log("Form submitting, saving materials...");
      saveExpenseMaterials(issueId, this);
    });
  }
  
  function loadSavedMaterials(issueId) {
    console.log("Loading saved materials for issue:", issueId);
    
    $.ajax({
      url: '/expense/issue_materials',
      method: 'GET',
      data: { issue_id: issueId },
      dataType: 'json',
      success: function(materials) {
        console.log("Saved materials loaded:", materials);
        if (materials.length > 0) {
          addExpenseFieldsWithData(materials, issueId);
        } else {
          addExpenseFields(issueId);
        }
      },
      error: function(xhr) {
        console.log("Error loading saved materials:", xhr.responseText);
        addExpenseFields(issueId);
      }
    });
  }
  
  function addExpenseFieldsWithData(materials, issueId) {
    if ($('#expense-fields-container').length > 0) {
      return;
    }
    
    console.log("Adding expense fields with saved data...");
    
    var html = `
      <div id="expense-fields-container">
        <div class="expense-fields">
          <h3>Расходные материалы</h3>
          <p class="expense-hint">Добавьте расходные материалы, использованные при решении задачи</p>
          <div class="expense-materials">
            <div id="expense-materials-container">
    `;
    
    if (materials && materials.length > 0) {
      materials.forEach(function(material) {
        html += `
          <div class="expense-material-row" data-material-id="${material.id}">
            <select name="expense[material_type][]" class="expense-type-select" style="width:20%; margin-right:5px;">
              <option value="">Выберите тип</option>
            </select>
            <select name="expense[brand][]" class="expense-brand-select" style="width:20%; margin-right:5px;">
              <option value="">Выберите бренд</option>
            </select>
            <select name="expense[model][]" class="expense-model-select" style="width:20%; margin-right:5px;">
              <option value="">Выберите модель</option>
            </select>
            <input type="text" name="expense[quantity][]" value="${material.quantity}" placeholder="Кол-во" class="expense-quantity-input" style="width:8%; margin-right:5px;">
            <span class="stock-info" style="width:15%; font-size:11px; color:#666;">Загрузка...</span>
            <a href="#" class="remove-expense-material" style="color:#999; text-decoration:none; font-size:18px; font-weight:bold; padding:0 8px;">✕</a>
            <input type="hidden" name="expense[id][]" value="${material.id}">
          </div>
        `;
      });
    }
    
    html += `
            </div>
            <a href="#" class="add-expense-material" style="display:inline-block; margin-top:10px; color:#3e5b76; text-decoration:none; cursor:pointer;">+ Добавить материал</a>
          </div>
        </div>
      </div>
    `;
    
    $('#add_notes').after(html);
    
    loadAllTypes(function() {
      $('.expense-material-row').each(function(index) {
        var row = $(this);
        var material = materials[index];
        if (material) {
          var typeSelect = row.find('.expense-type-select');
          var brandSelect = row.find('.expense-brand-select');
          var modelSelect = row.find('.expense-model-select');
          
          typeSelect.val(material.material_type);
          loadBrandsForRow(row, material, issueId);
        }
      });
    });
  }
  
  function addExpenseFields(issueId) {
    if ($('#expense-fields-container').length > 0) {
      return;
    }
    
    console.log("Adding expense fields...");
    
    var html = `
      <div id="expense-fields-container">
        <div class="expense-fields">
          <h3>Расходные материалы</h3>
          <p class="expense-hint">Добавьте расходные материалы, использованные при решении задачи</p>
          <div class="expense-materials">
            <div id="expense-materials-container">
              <div class="expense-material-row">
                <select name="expense[material_type][]" class="expense-type-select" style="width:20%; margin-right:5px;">
                  <option value="">Выберите тип</option>
                </select>
                <select name="expense[brand][]" class="expense-brand-select" style="width:20%; margin-right:5px;" disabled>
                  <option value="">Выберите бренд</option>
                </select>
                <select name="expense[model][]" class="expense-model-select" style="width:20%; margin-right:5px;" disabled>
                  <option value="">Выберите модель</option>
                </select>
                <input type="text" name="expense[quantity][]" placeholder="Кол-во" class="expense-quantity-input" style="width:8%; margin-right:5px;">
                <span class="stock-info" style="width:15%; font-size:11px; color:#666;">Доступно: ?</span>
                <a href="#" class="remove-expense-material" style="color:#999; text-decoration:none; font-size:18px; font-weight:bold; padding:0 8px;">✕</a>
              </div>
            </div>
            <a href="#" class="add-expense-material" style="display:inline-block; margin-top:10px; color:#3e5b76; text-decoration:none; cursor:pointer;">+ Добавить материал</a>
          </div>
        </div>
      </div>
    `;
    
    $('#add_notes').after(html);
    loadAllTypes();
  }
  
  function loadAllTypes(callback) {
    $.ajax({
      url: '/expense/materials',
      method: 'GET',
      dataType: 'json',
      success: function(data) {
        var selects = $('.expense-type-select');
        selects.each(function() {
          var select = $(this);
          select.find('option:not(:first)').remove();
          $.each(data, function(i, type) {
            select.append('<option value="' + type.id + '">' + type.name + '</option>');
          });
        });
        if (callback) callback();
      }
    });
  }
  
  function loadBrandsForRow(row, material, issueId) {
    var typeSelect = row.find('.expense-type-select');
    var brandSelect = row.find('.expense-brand-select');
    var modelSelect = row.find('.expense-model-select');
    var materialType = typeSelect.val();
    
    if (!materialType) return;
    
    brandSelect.prop('disabled', true);
    brandSelect.find('option:not(:first)').remove();
    
    $.ajax({
      url: '/expense/brands',
      method: 'GET',
      data: { material_type: materialType },
      dataType: 'json',
      success: function(data) {
        brandSelect.prop('disabled', false);
        $.each(data, function(i, brand) {
          brandSelect.append('<option value="' + brand.id + '">' + brand.name + '</option>');
        });
        if (material && material.brand) {
          brandSelect.val(material.brand);
          loadModelsForRow(row, material, issueId);
        }
      }
    });
  }
  
  function loadModelsForRow(row, material, issueId) {
    var typeSelect = row.find('.expense-type-select');
    var brandSelect = row.find('.expense-brand-select');
    var modelSelect = row.find('.expense-model-select');
    var materialType = typeSelect.val();
    var brand = brandSelect.val();
    
    if (!materialType || !brand) return;
    
    modelSelect.prop('disabled', true);
    modelSelect.find('option:not(:first)').remove();
    
    $.ajax({
      url: '/expense/models',
      method: 'GET',
      data: { material_type: materialType, brand: brand },
      dataType: 'json',
      success: function(data) {
        modelSelect.prop('disabled', false);
        $.each(data, function(i, model) {
          modelSelect.append('<option value="' + model.id + '">' + model.name + '</option>');
        });
        if (material && material.model) {
          modelSelect.val(material.model);
          checkStock(row, issueId);
        }
      }
    });
  }
  
  function loadBrands(typeSelect) {
    var row = typeSelect.closest('.expense-material-row');
    var brandSelect = row.find('.expense-brand-select');
    var modelSelect = row.find('.expense-model-select');
    var stockInfo = row.find('.stock-info');
    var materialType = typeSelect.val();
    var issueId = window.currentIssueId || $('#issue-form').find('input[name="id"]').val();
    
    brandSelect.prop('disabled', true);
    modelSelect.prop('disabled', true);
    brandSelect.val('');
    modelSelect.val('');
    brandSelect.find('option:not(:first)').remove();
    modelSelect.find('option:not(:first)').remove();
    stockInfo.text('Доступно: ?');
    
    if (materialType) {
      $.ajax({
        url: '/expense/brands',
        method: 'GET',
        data: { material_type: materialType },
        dataType: 'json',
        success: function(data) {
          brandSelect.prop('disabled', false);
          $.each(data, function(i, brand) {
            brandSelect.append('<option value="' + brand.id + '">' + brand.name + '</option>');
          });
        }
      });
    }
  }
  
  function loadModels(row, type, brand) {
    var modelSelect = row.find('.expense-model-select');
    var stockInfo = row.find('.stock-info');
    var issueId = window.currentIssueId || $('#issue-form').find('input[name="id"]').val();
    
    modelSelect.prop('disabled', true);
    modelSelect.val('');
    modelSelect.find('option:not(:first)').remove();
    stockInfo.text('Доступно: ?');
    
    if (type && brand) {
      $.ajax({
        url: '/expense/models',
        method: 'GET',
        data: { material_type: type, brand: brand },
        dataType: 'json',
        success: function(data) {
          modelSelect.prop('disabled', false);
          $.each(data, function(i, model) {
            modelSelect.append('<option value="' + model.id + '">' + model.name + '</option>');
          });
        }
      });
    }
  }
  
  function checkStock(row, issueId) {
    var typeSelect = row.find('.expense-type-select');
    var brandSelect = row.find('.expense-brand-select');
    var modelSelect = row.find('.expense-model-select');
    var stockInfo = row.find('.stock-info');
    var quantityInput = row.find('.expense-quantity-input');
    
    var materialType = typeSelect.val();
    var brand = brandSelect.val();
    var model = modelSelect.val();
    
    if (!materialType || !brand || !model) {
      stockInfo.text('Доступно: ?');
      return;
    }
    
    var url = '/expense/stock_quantity';
    var params = {
      material_type: materialType,
      brand: brand,
      model: model
    };
    
    if (issueId) {
      params.issue_id = issueId;
    }
    
    $.ajax({
      url: url,
      method: 'GET',
      data: params,
      dataType: 'json',
      success: function(data) {
        var infoText = '';
        
        if (data.available) {
          var available = data.available_quantity || data.quantity;
          infoText = '📦 Всего: ' + data.quantity;
          
          if (data.pending_quantity > 0) {
            infoText += ' | ⏳ Ожидает: ' + data.pending_quantity;
          }
          
          infoText += ' | ✅ Доступно: ' + available;
          stockInfo.html('<span style="color: green;">' + infoText + '</span>');
          
          // Проверяем количество
          var entered = parseFloat(quantityInput.val()) || 0;
          if (entered > available) {
            quantityInput.css('border-color', 'red');
            stockInfo.html('<span style="color: red;">⚠️ ' + infoText + ' (превышение!)</span>');
          } else {
            quantityInput.css('border-color', '');
          }
        } else {
          stockInfo.html('<span style="color: red;">❌ Нет в наличии</span>');
        }
      },
      error: function() {
        stockInfo.text('❌ Ошибка загрузки');
      }
    });
  }
  
  // Проверка количества при вводе
  $(document).on('input', '.expense-quantity-input', function() {
    var row = $(this).closest('.expense-material-row');
    var issueId = $('#issue-form').find('input[name="id"]').val();
    checkStock(row, issueId);
  });
  
  // Проверка при изменении модели
  $(document).on('change', '.expense-model-select', function() {
    var row = $(this).closest('.expense-material-row');
    var issueId = $('#issue-form').find('input[name="id"]').val();
    checkStock(row, issueId);
  });
  
  function saveExpenseMaterials(issueId, form) {
    console.log("Saving materials for issue:", issueId);
    
    var materials = [];
    var removeIds = [];
    var hasErrors = false;
    
    $('.expense-material-row').each(function() {
      var row = $(this);
      var materialType = row.find('.expense-type-select').val();
      var brand = row.find('.expense-brand-select').val();
      var model = row.find('.expense-model-select').val();
      var quantity = row.find('.expense-quantity-input').val();
      var id = row.find('input[name="expense[id][]"]').val();
      var stockInfo = row.find('.stock-info');
      
      var removeInput = row.find('input[name="expense[remove_ids][]"]');
      if (removeInput.length > 0) {
        removeIds.push(removeInput.val());
      }
      
      if (materialType && brand && model && quantity) {
        var quantityNum = parseFloat(quantity);
        var stockText = stockInfo.text();
        var match = stockText.match(/Доступно:\s*([\d.]+)/);
        if (match) {
          var available = parseFloat(match[1]);
          if (quantityNum > available) {
            hasErrors = true;
            alert('❌ Недостаточно материала "' + brand + ' ' + model + '".\nДоступно: ' + available + ', запрошено: ' + quantityNum);
            return false;
          }
        }
        
        materials.push({
          material_type: materialType,
          brand: brand,
          model: model,
          quantity: quantity,
          id: id
        });
      }
    });
    
    if (hasErrors) {
      return;
    }
    
    console.log("Materials to save:", materials);
    console.log("Materials to remove:", removeIds);
    
    if (materials.length > 0 || removeIds.length > 0) {
      $.ajax({
        url: '/expense/save',
        method: 'POST',
        data: {
          issue_id: issueId,
          materials: materials,
          remove_ids: removeIds
        },
        dataType: 'json',
        async: false,
        success: function(response) {
          console.log("Materials saved successfully:", response);
          form.submit();
        },
        error: function(xhr) {
          console.log("Error saving materials:", xhr.responseText);
          try {
            var response = JSON.parse(xhr.responseText);
            var message = response.error || 'Неизвестная ошибка';
            alert('⚠️ Ошибка при сохранении материалов:\n' + message);
          } catch(e) {
            alert('⚠️ Ошибка при сохранении материалов. Попробуйте еще раз.');
          }
          form.submit();
        }
      });
    } else {
      console.log("No materials to save, submitting form");
      form.submit();
    }
  }
  
  $(document).on('change', '.expense-type-select', function() {
    loadBrands($(this));
  });
  
  $(document).on('change', '.expense-brand-select', function() {
    var brandSelect = $(this);
    var row = brandSelect.closest('.expense-material-row');
    var typeSelect = row.find('.expense-type-select');
    loadModels(row, typeSelect.val(), brandSelect.val());
  });
  
  $(document).on('click', '.add-expense-material', function(e) {
    e.preventDefault();
    var issueId = $('#issue-form').find('input[name="id"]').val();
    
    var container = $('#expense-materials-container');
    var firstRow = container.find('.expense-material-row:first');
    
    if (firstRow.length) {
      var newRow = firstRow.clone();
      
      newRow.find('.expense-type-select').val('');
      newRow.find('.expense-brand-select').val('').prop('disabled', true);
      newRow.find('.expense-model-select').val('').prop('disabled', true);
      newRow.find('.expense-quantity-input').val('');
      newRow.find('.stock-info').text('Доступно: ?');
      newRow.find('input[name="expense[id][]"]').remove();
      
      newRow.find('.expense-brand-select option:not(:first)').remove();
      newRow.find('.expense-model-select option:not(:first)').remove();
      
      container.append(newRow);
      
      var typeSelect = newRow.find('.expense-type-select');
      $.ajax({
        url: '/expense/materials',
        method: 'GET',
        dataType: 'json',
        success: function(data) {
          typeSelect.find('option:not(:first)').remove();
          $.each(data, function(i, type) {
            typeSelect.append('<option value="' + type.id + '">' + type.name + '</option>');
          });
        }
      });
    }
  });
  
  $(document).on('click', '.remove-expense-material', function(e) {
    e.preventDefault();
    var row = $(this).closest('.expense-material-row');
    var count = $('.expense-material-row').length;
    
    if (count > 1) {
      var id = row.find('input[name="expense[id][]"]').val();
      if (id) {
        row.append('<input type="hidden" name="expense[remove_ids][]" value="' + id + '">');
      }
      row.remove();
    } else {
      alert('Должна быть хотя бы одна строка с материалом');
    }
  });
});
