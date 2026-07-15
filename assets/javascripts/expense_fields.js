$(document).ready(function() {
  var root = $('#expense-fields-root');
  if (root.length === 0) return; // плагин отключен для этого проекта/трекера/статусов

  var issueId = root.data('issue-id') || window.currentIssueId;
  var statusInProgress = (window.expenseSettings && window.expenseSettings.statusInProgress) || [];
  var statusResolved = (window.expenseSettings && window.expenseSettings.statusResolved) || [];
  var allStatuses = statusInProgress.concat(statusResolved).map(String);

  initExpenseFields(issueId);

  function initExpenseFields(issueId) {
    var statusId = String($('#issue_status_id').val());

    if (allStatuses.indexOf(statusId) !== -1) {
      loadSavedMaterials(issueId);
    }

    $('#issue_status_id').on('change', function() {
      var newStatus = String($(this).val());
      if (allStatuses.indexOf(newStatus) !== -1) {
        if ($('#expense-fields-container').length === 0) {
          loadSavedMaterials(issueId);
        }
      } else {
        $('#expense-fields-container').remove();
      }
    });

    $('#issue-form').on('submit', function(e) {
      if ($('#expense-fields-container').length === 0) return; // нечего сохранять
      e.preventDefault();
      saveExpenseMaterials(issueId, this);
    });
  }

  function loadSavedMaterials(issueId) {
    $.ajax({
      url: '/expense/issue_materials',
      method: 'GET',
      data: { issue_id: issueId },
      dataType: 'json',
      success: function(materials) {
        renderExpenseFields(materials || [], issueId);
      },
      error: function() {
        renderExpenseFields([], issueId);
      }
    });
  }

  function buildRow(material) {
    var id = material ? material.id : '';
    var quantity = material ? material.quantity : '';
    return $(
      '<div class="expense-material-row" data-material-id="' + id + '">' +
        '<select name="expense[material_type][]" class="expense-type-select"><option value="">Выберите тип</option></select>' +
        '<div class="expense-brand-wrap">' +
          '<input type="text" class="expense-brand-input" placeholder="Начните вводить наименование" autocomplete="off" disabled>' +
          '<input type="hidden" name="expense[brand][]" class="expense-brand-value">' +
          '<ul class="expense-brand-suggestions"></ul>' +
        '</div>' +
        '<select name="expense[model][]" class="expense-model-select" disabled><option value="">Выберите модель</option></select>' +
        '<input type="text" name="expense[quantity][]" value="' + (quantity || '') + '" placeholder="Кол-во" class="expense-quantity-input">' +
        '<span class="stock-info">Доступно: ?</span>' +
        '<a href="#" class="remove-expense-material" title="Удалить">&#10005;</a>' +
        (id ? '<input type="hidden" name="expense[id][]" value="' + id + '">' : '') +
      '</div>'
    );
  }

  function renderExpenseFields(materials, issueId) {
    if ($('#expense-fields-container').length > 0) return;

    var html =
      '<div id="expense-fields-container">' +
        '<div class="expense-fields">' +
          '<h3>Расходные материалы</h3>' +
          '<p class="expense-hint">Добавьте расходные материалы, использованные при решении задачи</p>' +
          '<div class="expense-materials">' +
            '<div id="expense-materials-container"></div>' +
            '<a href="#" class="add-expense-material">+ Добавить материал</a>' +
          '</div>' +
        '</div>' +
      '</div>';

    root.html(html);

    var container = $('#expense-materials-container');
    var rows = materials.length > 0 ? materials : [null];

    rows.forEach(function(material) {
      container.append(buildRow(material));
    });

    loadAllTypes(function() {
      $('.expense-material-row').each(function(index) {
        var row = $(this);
        var material = materials[index];
        if (material) {
          row.find('.expense-type-select').val(material.material_type);
          loadBrandsForRow(row, material, issueId);
        }
      });
    });
  }

  function loadAllTypes(callback) {
    $.ajax({
      url: '/expense/materials',
      method: 'GET',
      dataType: 'json',
      success: function(data) {
        $('.expense-type-select').each(function() {
          var select = $(this);
          var current = select.val();
          select.find('option:not(:first)').remove();
          $.each(data, function(i, type) {
            select.append('<option value="' + type.id + '">' + type.name + '</option>');
          });
          if (current) select.val(current);
        });
        if (callback) callback();
      }
    });
  }

  // Загружает полный список брендов/наименований для выбранного типа один раз
  // и кэширует его на строке — дальше поиск при вводе идёт по кэшу, без
  // повторных запросов на каждое нажатие клавиши.
  function loadBrandsForRow(row, material, issueId) {
    var brandInput = row.find('.expense-brand-input');
    var brandValue = row.find('.expense-brand-value');
    var materialType = row.find('.expense-type-select').val();

    row.data('brandOptions', []);
    brandInput.prop('disabled', true).val('');
    brandValue.val('');
    hideSuggestions(row);
    resetModelSelect(row);

    if (!materialType) return;

    $.ajax({
      url: '/expense/brands',
      method: 'GET',
      data: { material_type: materialType },
      dataType: 'json',
      success: function(data) {
        row.data('brandOptions', data || []);
        brandInput.prop('disabled', false);

        if (material && material.brand) {
          brandInput.val(material.brand);
          brandValue.val(material.brand);
          loadModelsForRow(row, material, issueId);
        }
      }
    });
  }

  function resetModelSelect(row) {
    row.find('.expense-model-select').prop('disabled', true).val('').find('option:not(:first)').remove();
    row.find('.stock-info').text('Доступно: ?');
  }

  function hideSuggestions(row) {
    row.find('.expense-brand-suggestions').empty().hide();
  }

  function renderSuggestions(row, query) {
    var list = row.data('brandOptions') || [];
    var suggestionsEl = row.find('.expense-brand-suggestions');
    suggestionsEl.empty();

    var q = query.trim().toLowerCase();
    var matches = q.length === 0 ? list : list.filter(function(item) {
      return item.name.toLowerCase().indexOf(q) !== -1;
    });

    if (matches.length === 0) {
      suggestionsEl.append('<li class="expense-brand-empty">Ничего не найдено</li>');
      suggestionsEl.show();
      return;
    }

    matches.slice(0, 50).forEach(function(item) {
      var li = $('<li></li>').text(item.name).attr('data-value', item.id);
      suggestionsEl.append(li);
    });
    suggestionsEl.show();
  }

  function selectBrand(row, value, issueId) {
    row.find('.expense-brand-input').val(value);
    row.find('.expense-brand-value').val(value);
    hideSuggestions(row);
    resetModelSelect(row);
    loadModelsForRow(row, null, issueId);
  }

  function loadModelsForRow(row, material, issueId) {
    var modelSelect = row.find('.expense-model-select');
    var materialType = row.find('.expense-type-select').val();
    var brand = row.find('.expense-brand-value').val();
    if (!materialType || !brand) return;

    modelSelect.prop('disabled', true).find('option:not(:first)').remove();

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

  function checkStock(row, issueId) {
    var materialType = row.find('.expense-type-select').val();
    var brand = row.find('.expense-brand-value').val();
    var model = row.find('.expense-model-select').val();
    var stockInfo = row.find('.stock-info');
    var quantityInput = row.find('.expense-quantity-input');

    if (!materialType || !brand || !model) {
      stockInfo.text('Доступно: ?');
      return;
    }

    var params = { material_type: materialType, brand: brand, model: model };
    if (issueId) params.issue_id = issueId;

    $.ajax({
      url: '/expense/stock_quantity',
      method: 'GET',
      data: params,
      dataType: 'json',
      success: function(data) {
        if (!data.available) {
          stockInfo.html('<span class="stock-danger">Нет в наличии</span>');
          return;
        }

        var available = data.available_quantity;
        var infoText = 'Всего: ' + data.quantity;
        if (data.pending_quantity > 0) infoText += ' | Ожидает: ' + data.pending_quantity;
        infoText += ' | Доступно: ' + available;

        var entered = parseFloat(quantityInput.val()) || 0;
        if (entered > available) {
          stockInfo.html('<span class="stock-danger">' + infoText + ' (превышение!)</span>');
        } else {
          stockInfo.html('<span class="stock-ok">' + infoText + '</span>');
        }
      },
      error: function() {
        stockInfo.text('Ошибка загрузки остатка');
      }
    });
  }

  $(document).on('change', '.expense-type-select', function() {
    var row = $(this).closest('.expense-material-row');
    loadBrandsForRow(row, null, issueId);
  });

  // Живой поиск: фильтруем закэшированный список брендов/наименований
  // при каждом вводе символа. Любое ручное изменение текста сбрасывает
  // ранее выбранное значение — пока пользователь не кликнет по подсказке,
  // строка считается незаполненной.
  $(document).on('input', '.expense-brand-input', function() {
    var row = $(this).closest('.expense-material-row');
    row.find('.expense-brand-value').val('');
    resetModelSelect(row);
    renderSuggestions(row, $(this).val());
  });

  $(document).on('focus', '.expense-brand-input', function() {
    var row = $(this).closest('.expense-material-row');
    if (!$(this).prop('disabled')) {
      renderSuggestions(row, $(this).val());
    }
  });

  // mousedown, а не click — чтобы подсказка успела выбраться раньше,
  // чем blur инпута скроет список подсказок.
  $(document).on('mousedown', '.expense-brand-suggestions li[data-value]', function(e) {
    e.preventDefault();
    var row = $(this).closest('.expense-material-row');
    selectBrand(row, $(this).attr('data-value'), issueId);
  });

  $(document).on('blur', '.expense-brand-input', function() {
    var row = $(this).closest('.expense-material-row');
    setTimeout(function() { hideSuggestions(row); }, 150);
  });

  $(document).on('change', '.expense-model-select', function() {
    checkStock($(this).closest('.expense-material-row'), issueId);
  });

  $(document).on('input', '.expense-quantity-input', function() {
    checkStock($(this).closest('.expense-material-row'), issueId);
  });

  $(document).on('click', '.add-expense-material', function(e) {
    e.preventDefault();
    var container = $('#expense-materials-container');
    var row = buildRow(null);
    container.append(row);
    loadAllTypes();
  });

  $(document).on('click', '.remove-expense-material', function(e) {
    e.preventDefault();
    var row = $(this).closest('.expense-material-row');
    var count = $('.expense-material-row').length;

    if (count <= 1) {
      alert('Должна быть хотя бы одна строка с материалом');
      return;
    }

    var id = row.data('material-id');
    if (id) {
      $('#expense-materials-container').append('<input type="hidden" name="expense[remove_ids][]" value="' + id + '">');
    }
    row.remove();
  });

  function saveExpenseMaterials(issueId, form) {
    var materials = [];
    var removeIds = [];
    var hasErrors = false;

    $('#expense-materials-container input[name="expense[remove_ids][]"]').each(function() {
      removeIds.push($(this).val());
    });

    $('.expense-material-row').each(function() {
      var row = $(this);
      var materialType = row.find('.expense-type-select').val();
      var brandTyped = row.find('.expense-brand-input').val();
      var brand = row.find('.expense-brand-value').val();
      var model = row.find('.expense-model-select').val();
      var quantity = row.find('.expense-quantity-input').val();
      var id = row.find('input[name="expense[id][]"]').val();

      if (!materialType && !brandTyped && !model && !quantity) return; // пустая строка

      if (brandTyped && !brand) {
        hasErrors = true;
        alert('Выберите наименование/бренд из выпадающего списка подсказок, а не просто впишите текст.');
        return false;
      }

      if (!materialType || !brand || !model || !quantity) {
        hasErrors = true;
        alert('Заполните тип, наименование, модель и количество материала во всех строках.');
        return false;
      }

      var quantityNum = parseFloat(quantity);
      if (isNaN(quantityNum) || quantityNum <= 0) {
        hasErrors = true;
        alert('Количество должно быть больше нуля.');
        return false;
      }

      var stockText = row.find('.stock-info').text();
      var match = stockText.match(/Доступно:\s*([\d.]+)/);
      if (match) {
        var available = parseFloat(match[1]);
        if (quantityNum > available) {
          hasErrors = true;
          alert('Недостаточно материала "' + brand + ' ' + model + '".\nДоступно: ' + available + ', запрошено: ' + quantityNum);
          return false;
        }
      }

      materials.push({ material_type: materialType, brand: brand, model: model, quantity: quantity, id: id });
    });

    if (hasErrors) return;

    if (materials.length === 0 && removeIds.length === 0) {
      form.submit();
      return;
    }

    $.ajax({
      url: '/expense/save',
      method: 'POST',
      data: { issue_id: issueId, materials: materials, remove_ids: removeIds },
      dataType: 'json',
      success: function() {
        form.submit();
      },
      error: function(xhr) {
        var message = 'Неизвестная ошибка';
        try {
          message = JSON.parse(xhr.responseText).error || message;
        } catch (e) { /* noop */ }
        alert('Ошибка при сохранении материалов:\n' + message);
      }
    });
  }
});
