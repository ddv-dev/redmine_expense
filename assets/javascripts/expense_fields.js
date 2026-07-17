$(document).ready(function() {
  if ($('#expense-fields-root').length === 0) return; // плагин отключен для этого проекта/трекера

  var issueId = $('#expense-fields-root').data('issue-id') || window.currentIssueId;
  var projectId = window.currentProjectId;
  var expenseBase = '/projects/' + projectId + '/expense';
  // materialStatuses — основной источник; statusInProgress/statusResolved —
  // fallback на случай, когда страница отрендерена старой версией партиала.
  var expenseSettings = window.expenseSettings || {};
  var allStatuses = (expenseSettings.materialStatuses ||
                     [].concat(expenseSettings.statusInProgress || [], expenseSettings.statusResolved || [])).map(String);

  var typesCache = null; // общий для всех строк список типов материала

  function log() {
    if (window.console && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift('[redmine_expense]');
      console.log.apply(console, args);
    }
  }

  log('init, issueId =', issueId, 'projectId =', projectId, 'allStatuses =', allStatuses);

  function statusAllowsEditing() {
    return allStatuses.indexOf(String($('#issue_status_id').val())) !== -1;
  }

  // Помечаем текущий root как обработанный: Redmine перерисовывает форму
  // задачи AJAX'ом при смене статуса/трекера, при этом появляется НОВЫЙ
  // #expense-fields-root без этой пометки — так мы понимаем, что блок
  // нужно отрисовать заново.
  function markRootInitialized() {
    var rootEl = document.getElementById('expense-fields-root');
    if (rootEl) rootEl.setAttribute('data-expense-init', '1');
  }

  function refreshExpenseFields() {
    markRootInitialized();
    $('#expense-fields-container').remove();
    loadSavedMaterials(issueId);
  }

  refreshExpenseFields();

  // Смена статуса прямо в форме (без перерисовки формы Redmine'ом).
  $(document).on('change', '#issue_status_id', function() {
    refreshExpenseFields();
  });

  // Перерисовка формы Redmine'ом (updateIssueFrom): старый root вместе с
  // нашим контейнером выбрасывается из DOM, в новой форме root пустой.
  $(document).ajaxComplete(function() {
    var rootEl = document.getElementById('expense-fields-root');
    if (rootEl && !rootEl.getAttribute('data-expense-init')) {
      refreshExpenseFields();
    }
  });

  $(document).on('submit', '#issue-form', function(e) {
    var container = $('#expense-fields-container');
    if (container.length === 0) return; // нечего сохранять
    if (container.attr('data-editable') !== '1') return; // режим просмотра
    e.preventDefault();
    saveExpenseMaterials(issueId, this);
  });

  function loadSavedMaterials(issueId) {
    $.ajax({
      url: expenseBase + '/issue_materials',
      method: 'GET',
      data: { issue_id: issueId },
      dataType: 'json',
      success: function(materials) {
        log('issue_materials loaded:', materials);
        renderExpenseFields(materials || [], issueId);
      },
      error: function(xhr) {
        log('issue_materials FAILED, status =', xhr.status, xhr.responseText);
        renderExpenseFields([], issueId);
      }
    });
  }

  function buildRow(material, editable) {
    var id = material ? material.id : '';
    var materialStockId = material ? material.material_stock_id : '';
    var quantity = material ? material.quantity : '';
    var disabledAttr = editable ? '' : ' disabled';
    return $(
      '<div class="expense-material-row" data-material-id="' + id + '">' +
        '<div class="expense-autocomplete-wrap">' +
          '<input type="text" class="expense-type-input" placeholder="Начните вводить номенклатуру" autocomplete="off"' + disabledAttr + '>' +
          '<input type="hidden" name="expense[material_name][]" class="expense-type-value">' +
          '<ul class="expense-type-suggestions expense-suggestions"></ul>' +
        '</div>' +
        '<input type="text" name="expense[quantity][]" value="' + (quantity || '') + '" placeholder="Кол-во" class="expense-quantity-input"' + disabledAttr + '>' +
        (editable ? '<span class="stock-info">Доступно: ?</span>' : '') +
        (editable ? '<a href="#" class="remove-expense-material" title="Удалить">&#10005;</a>' : '') +
        '<input type="hidden" name="expense[material_stock_id][]" class="expense-material-stock-id" value="' + (materialStockId || '') + '">' +
        (id ? '<input type="hidden" name="expense[id][]" value="' + id + '">' : '') +
      '</div>'
    );
  }

  function renderExpenseFields(materials, issueId) {
    var root = $('#expense-fields-root');
    if (root.length === 0) return;
    if ($('#expense-fields-container').length > 0) return;

    var editable = statusAllowsEditing();

    // В "запрещенном" статусе блок показывается только для просмотра уже
    // добавленных материалов; если их нет — не показывается вообще.
    if (!editable && materials.length === 0) return;

    var hint = editable ?
      'Добавьте расходные материалы, использованные при решении задачи' :
      'Материалы, списанные в этой задаче. Добавление и изменение недоступно в текущем статусе';

    var html =
      '<div id="expense-fields-container" data-editable="' + (editable ? '1' : '0') + '">' +
        '<div class="expense-fields">' +
          '<h3>Расходные материалы</h3>' +
          '<p class="expense-hint">' + hint + '</p>' +
          '<div class="expense-materials">' +
            '<div id="expense-materials-container"></div>' +
            (editable ? '<a href="#" class="add-expense-material">+ Добавить материал</a>' : '') +
          '</div>' +
        '</div>' +
      '</div>';

    root.html(html);

    var container = $('#expense-materials-container');
    var rows = materials.length > 0 ? materials : [null];

    rows.forEach(function(material) {
      container.append(buildRow(material, editable));
    });

    var fillSaved = function() {
      $('.expense-material-row').each(function(index) {
        var row = $(this);
        var material = materials[index];
        if (material) {
          row.find('.expense-type-input').val(material.material_name);
          row.find('.expense-type-value').val(material.material_name);
          if (editable) checkStock(row, issueId);
        }
      });
    };

    if (editable) {
      ensureTypesLoaded(fillSaved);
    } else {
      fillSaved();
    }
  }

  // Загружает список типов материала один раз и переиспользует его для всех
  // строк и подсказок — повторных запросов на сервер при вводе не требуется.
  function ensureTypesLoaded(callback) {
    if (typesCache) {
      if (callback) callback();
      return;
    }

    $.ajax({
      url: expenseBase + '/materials',
      method: 'GET',
      dataType: 'json',
      success: function(data) {
        typesCache = data || [];
        log('types loaded:', typesCache.length);
        if (callback) callback();
      },
      error: function(xhr) {
        log('materials (types) FAILED, status =', xhr.status, xhr.responseText);
      }
    });
  }

  // Наименование поставщика и модификация больше не выбираются вручную —
  // для выбранной номенклатуры всегда берется первая заведенная на складе
  // проекта позиция (server: MaterialStock.order(:id).first).
  function resolveStock(row, issueId) {
    var materialName = row.find('.expense-type-value').val();
    resetStock(row);

    if (!materialName) return;

    $.ajax({
      url: expenseBase + '/resolve_stock',
      method: 'GET',
      data: { material_name: materialName },
      dataType: 'json',
      success: function(data) {
        if (!data || !data.id) {
          row.find('.stock-info').html('<span class="stock-danger">Материал не найден на складе</span>');
          return;
        }
        row.find('.expense-material-stock-id').val(data.id);
        checkStock(row, issueId);
      },
      error: function(xhr) {
        log('resolve_stock FAILED, status =', xhr.status, xhr.responseText);
        row.find('.stock-info').html('<span class="stock-danger">Материал не найден на складе</span>');
      }
    });
  }

  function resetStock(row) {
    row.find('.expense-material-stock-id').val('');
    row.find('.stock-info').text('Доступно: ?');
  }

  function hideSuggestions(row, field) {
    row.find('.expense-' + field + '-suggestions').empty().hide();
  }

  function renderSuggestionList(suggestionsEl, list, query) {
    suggestionsEl.empty();

    var q = query.trim().toLowerCase();
    var matches = q.length === 0 ? list : list.filter(function(item) {
      return item.name.toLowerCase().indexOf(q) !== -1;
    });

    if (matches.length === 0) {
      suggestionsEl.append('<li class="expense-suggestion-empty">Ничего не найдено</li>');
      suggestionsEl.show();
      return;
    }

    matches.forEach(function(item) {
      var li = $('<li></li>').text(item.name).attr('data-value', item.id);
      suggestionsEl.append(li);
    });
    suggestionsEl.show();
  }

  function renderTypeSuggestions(row, query) {
    renderSuggestionList(row.find('.expense-type-suggestions'), typesCache || [], query);
  }

  function selectType(row, value, issueId) {
    row.find('.expense-type-input').val(value);
    row.find('.expense-type-value').val(value);
    hideSuggestions(row, 'type');
    resolveStock(row, issueId);
  }

  function checkStock(row, issueId) {
    var materialName = row.find('.expense-type-value').val();
    var materialStockId = row.find('.expense-material-stock-id').val();
    var stockInfo = row.find('.stock-info');
    var quantityInput = row.find('.expense-quantity-input');

    if (!materialName || !materialStockId) {
      stockInfo.text('Доступно: ?');
      return;
    }

    var params = { material_name: materialName, material_stock_id: materialStockId };
    if (issueId) params.issue_id = issueId;

    $.ajax({
      url: expenseBase + '/stock_quantity',
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
      error: function(xhr) {
        var message = 'Ошибка загрузки остатка';
        try {
          message = JSON.parse(xhr.responseText).error || message;
        } catch (e) { /* noop */ }
        log('stock_quantity FAILED, status =', xhr.status, 'params =', params, 'response =', xhr.responseText);
        stockInfo.html('<span class="stock-danger">' + message + '</span>');
      }
    });
  }

  // --- Тип материала: живой поиск по общему для всех строк списку ---

  $(document).on('input', '.expense-type-input', function() {
    var row = $(this).closest('.expense-material-row');
    row.find('.expense-type-value').val('');
    resetStock(row);
    renderTypeSuggestions(row, $(this).val());
  });

  $(document).on('focus', '.expense-type-input', function() {
    var input = $(this);
    var row = input.closest('.expense-material-row');
    ensureTypesLoaded(function() {
      renderTypeSuggestions(row, input.val());
    });
  });

  $(document).on('mousedown', '.expense-type-suggestions li[data-value]', function(e) {
    e.preventDefault();
    var row = $(this).closest('.expense-material-row');
    selectType(row, $(this).attr('data-value'), issueId);
  });

  $(document).on('blur', '.expense-type-input', function() {
    var row = $(this).closest('.expense-material-row');
    setTimeout(function() { hideSuggestions(row, 'type'); }, 150);
  });

  $(document).on('input', '.expense-quantity-input', function() {
    checkStock($(this).closest('.expense-material-row'), issueId);
  });

  $(document).on('click', '.add-expense-material', function(e) {
    e.preventDefault();
    var container = $('#expense-materials-container');
    var row = buildRow(null, true);
    container.append(row);
    ensureTypesLoaded();
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
      var typeTyped = row.find('.expense-type-input').val();
      var materialName = row.find('.expense-type-value').val();
      var materialStockId = row.find('.expense-material-stock-id').val();
      var quantity = row.find('.expense-quantity-input').val();
      var id = row.find('input[name="expense[id][]"]').val();

      if (!typeTyped && !quantity) return; // пустая строка

      if (typeTyped && !materialName) {
        hasErrors = true;
        alert('Выберите номенклатуру из выпадающего списка подсказок, а не просто впишите текст.');
        return false;
      }

      if (!materialName || !materialStockId || !quantity) {
        hasErrors = true;
        alert('Заполните номенклатуру и количество материала во всех строках.');
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
          alert('Недостаточно материала "' + materialName + '".\nДоступно: ' + available + ', запрошено: ' + quantityNum);
          return false;
        }
      }

      materials.push({
        material_name: materialName,
        material_stock_id: materialStockId,
        quantity: quantity,
        id: id
      });
    });

    if (hasErrors) return;

    if (materials.length === 0 && removeIds.length === 0) {
      log('save: nothing to save, submitting form as-is');
      form.submit();
      return;
    }

    var token = $('meta[name="csrf-token"]').attr('content');
    log('save: sending', { issue_id: issueId, materials: materials, remove_ids: removeIds }, 'csrf token present =', !!token);

    $.ajax({
      url: expenseBase + '/save',
      method: 'POST',
      data: { issue_id: issueId, materials: materials, remove_ids: removeIds },
      dataType: 'json',
      beforeSend: function(xhr) {
        if (token) xhr.setRequestHeader('X-CSRF-Token', token);
      },
      success: function(response) {
        log('save: OK', response);
        form.submit();
      },
      error: function(xhr) {
        var message = 'Неизвестная ошибка';
        try {
          message = JSON.parse(xhr.responseText).error || message;
        } catch (e) { /* noop */ }
        log('save: FAILED, status =', xhr.status, 'response =', xhr.responseText);
        alert('Ошибка при сохранении материалов (' + xhr.status + '):\n' + message);
      }
    });
  }
});
