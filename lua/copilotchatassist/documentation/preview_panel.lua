-- Panel de previsualización de documentación
-- Muestra la documentación propuesta antes de aplicarla y permite selección interactiva
local M = {}
local log = require("copilotchatassist.utils.log")
local utils = require("copilotchatassist.documentation.utils")
local i18n = require("copilotchatassist.i18n")

-- Estado del panel
M.state = {
  panel_bufnr = nil,          -- Buffer del panel
  panel_winnr = nil,          -- Ventana del panel
  original_winnr = nil,       -- Ventana original
  original_bufnr = nil,       -- Buffer original
  preview_items = {},         -- Elementos previsualización
  selected_indices = {},      -- Índices seleccionados
  panel_height = 15           -- Altura del panel
}

-- Tipos de elementos
local ITEM_TYPE = {
  NEW = "NEW",                -- Documentación nueva
  UPDATED = "UPDATED",        -- Documentación actualizada
  UNCHANGED = "UNCHANGED"     -- Documentación sin cambios
}

-- Obtener la traducción del tipo de elemento
local function get_type_text(type)
  if type == ITEM_TYPE.NEW then
    return i18n.t("preview.new_item")
  elseif type == ITEM_TYPE.UPDATED then
    return i18n.t("preview.update_item")
  else
    return i18n.t("preview.unchanged_item")
  end
}

-- Determina el tipo de un elemento de documentación comparando con el código existente
-- @param item table: El elemento a analizar
-- @param buffer number: ID del buffer
-- @return string: El tipo de elemento (NEW, UPDATED, UNCHANGED)
local function determine_item_type(item, buffer)
  local start_line = item.start_line
  local current_lines = vim.api.nvim_buf_get_lines(buffer, start_line - 2, start_line, false)

  -- Determinar si hay comentarios existentes
  local has_existing_docs = false
  for _, line in ipairs(current_lines) do
    if line:match("^%s*/%*%*") or       -- Java/JS style /** */
       line:match("^%s*%-%-%-") or      -- Lua style ---
       line:match("^%s*#") or           -- Python/Ruby style #
       line:match("^%s*//") then        -- C++ style //
      has_existing_docs = true
      break
    end
  end

  if not has_existing_docs then
    return ITEM_TYPE.NEW
  end

  -- Verificar si el elemento está marcado como modificado en git
  if item.changed then
    return ITEM_TYPE.UPDATED
  end

  return ITEM_TYPE.UNCHANGED
end

-- Genera la representación visual de un elemento para el panel
-- @param item table: El elemento a representar
-- @param idx number: Índice del elemento
-- @param is_selected boolean: Si está seleccionado
-- @return table: Líneas de texto para representar el elemento
local function generate_preview_lines(item, idx, is_selected)
  local lines = {}
  local item_type = item.preview_type
  local type_indicator

  -- Formatear el indicador del tipo de elemento
  type_indicator = get_type_text(item_type)

  -- Formatear el encabezado
  local selection_indicator = is_selected and "[x]" or "[ ]"
  table.insert(lines, string.format("%s %s #%d: %s (línea %d)",
                                   selection_indicator,
                                   type_indicator,
                                   idx,
                                   item.name or "elemento sin nombre",
                                   item.start_line))

  -- Separador
  table.insert(lines, string.rep("-", 50))

  -- Documentación propuesta
  local doc_preview = item.proposed_doc or "Sin documentación propuesta"
  for _, line in ipairs(vim.split(doc_preview, "\n")) do
    table.insert(lines, "  " .. line)
  end

  -- Separador final
  table.insert(lines, "")
  table.insert(lines, string.rep("=", 50))

  return lines
end

-- Actualiza el contenido del panel de previsualización
-- @param items table: Elementos a mostrar
-- @param selected_indices table: Índices de los elementos seleccionados
local function update_panel_content(items, selected_indices)
  if not M.state.panel_bufnr or not vim.api.nvim_buf_is_valid(M.state.panel_bufnr) then
    return
  end

  local lines = {
    i18n.t("preview.title"),
    i18n.t("preview.instructions"),
    i18n.t("preview.apply"),
    i18n.t("preview.close"),
    string.rep("=", 50),
    ""
  }

  selected_indices = selected_indices or M.state.selected_indices

  -- Generar líneas para cada elemento
  for idx, item in ipairs(items) do
    local is_selected = selected_indices[idx] or false
    local item_lines = generate_preview_lines(item, idx, is_selected)
    for _, line in ipairs(item_lines) do
      table.insert(lines, line)
    end
  end

  -- Actualizar el buffer del panel
  vim.api.nvim_buf_set_option(M.state.panel_bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.state.panel_bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.state.panel_bufnr, "modifiable", false)
end

-- Mapea las teclas para el panel
local function setup_panel_keymaps()
  if not M.state.panel_bufnr or not vim.api.nvim_buf_is_valid(M.state.panel_bufnr) then
    return
  end

  local function toggle_selection()
    if not M.state.panel_winnr or not vim.api.nvim_win_is_valid(M.state.panel_winnr) then
      return
    end

    -- Obtener línea actual
    local cursor = vim.api.nvim_win_get_cursor(M.state.panel_winnr)
    local line_content = vim.api.nvim_buf_get_lines(M.state.panel_bufnr, cursor[1] - 1, cursor[1], false)[1]

    -- Verificar si es una línea de encabezado de elemento
    local idx = line_content:match("^%[.%] %[.-%] #(%d+):")
    if not idx then return end

    -- Convertir a número
    idx = tonumber(idx)
    if not idx or idx < 1 or idx > #M.state.preview_items then return end

    -- Alternar selección
    M.state.selected_indices[idx] = not M.state.selected_indices[idx]

    -- Actualizar panel
    update_panel_content(M.state.preview_items, M.state.selected_indices)
  end

  local function apply_selected_items()
    local selected_items = {}
    for idx, selected in pairs(M.state.selected_indices) do
      if selected and M.state.preview_items[idx] then
        table.insert(selected_items, M.state.preview_items[idx].original_item)
      end
    end

    M.close_panel()

    -- Aplicar los elementos seleccionados
    if #selected_items > 0 then
      local doc_module = require("copilotchatassist.documentation")
      doc_module.process_items(selected_items)
    else
      vim.notify(i18n.t("preview.no_selection"), vim.log.levels.INFO)
    end
  end

  local function close_panel()
    M.close_panel()
  end

  -- Configurar mapeos de teclas
  local opts = { noremap = true, silent = true, buffer = M.state.panel_bufnr }
  vim.keymap.set("n", "<Space>", toggle_selection, opts)
  vim.keymap.set("n", "<CR>", apply_selected_items, opts)
  vim.keymap.set("n", "q", close_panel, opts)
end

-- Cierra el panel de previsualización
function M.close_panel()
  if M.state.panel_winnr and vim.api.nvim_win_is_valid(M.state.panel_winnr) then
    vim.api.nvim_win_close(M.state.panel_winnr, true)
  end

  M.state.panel_bufnr = nil
  M.state.panel_winnr = nil

  -- Volver a la ventana original
  if M.state.original_winnr and vim.api.nvim_win_is_valid(M.state.original_winnr) then
    vim.api.nvim_set_current_win(M.state.original_winnr)
  end
end

-- Genera la documentación propuesta para un elemento
-- @param item table: El elemento a documentar
-- @return string: La documentación propuesta
local function generate_proposed_documentation(item)
  local generator = require("copilotchatassist.documentation.generator")
  local doc = generator.generate_documentation_content(item)
  return doc or i18n.t("documentation.generation_failed")
end

-- Prepara los elementos para su visualización en el panel
-- @param items table: Elementos a preparar
-- @param buffer number: ID del buffer
-- @return table: Elementos preparados para visualización
local function prepare_preview_items(items, buffer)
  local preview_items = {}

  for _, item in ipairs(items) do
    -- Solo mostrar elementos que podemos documentar
    if item.content and item.start_line then
      -- Determinar tipo de elemento
      local item_type = determine_item_type(item, buffer)

      -- Generar documentación propuesta
      local proposed_doc = generate_proposed_documentation(item)

      table.insert(preview_items, {
        name = item.name or utils.extract_element_name(item),
        start_line = item.start_line,
        end_line = item.end_line,
        preview_type = item_type,
        proposed_doc = proposed_doc,
        original_item = item  -- Mantener referencia al elemento original
      })
    end
  end

  return preview_items
end

-- Crea y muestra el panel de previsualización
-- @param items table: Elementos a mostrar
-- @param buffer number: ID del buffer que contiene los elementos
function M.show_preview_panel(items, buffer)
  if not items or #items == 0 then
    vim.notify("No hay elementos para previsualizar", vim.log.levels.WARN)
    return
  end

  -- Guardar la ventana actual
  M.state.original_winnr = vim.api.nvim_get_current_win()
  M.state.original_bufnr = buffer

  -- Preparar elementos para previsualización
  M.state.preview_items = prepare_preview_items(items, buffer)

  -- Inicializar selecciones (por defecto todos seleccionados)
  M.state.selected_indices = {}
  for i = 1, #M.state.preview_items do
    -- Por defecto, seleccionar elementos nuevos y actualizados
    local item_type = M.state.preview_items[i].preview_type
    if item_type == ITEM_TYPE.NEW or item_type == ITEM_TYPE.UPDATED then
      M.state.selected_indices[i] = true
    end
  end

  -- Crear el buffer del panel
  M.state.panel_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.state.panel_bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(M.state.panel_bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(M.state.panel_bufnr, "swapfile", false)
  vim.api.nvim_buf_set_name(M.state.panel_bufnr, "DocPreview")

  -- Calcular dimensiones de la ventana
  local width = vim.api.nvim_get_option("columns")
  local height = vim.api.nvim_get_option("lines")
  local win_height = math.min(M.state.panel_height, math.floor(height * 0.8))
  local win_width = math.floor(width * 0.8)
  local row = math.floor((height - win_height) / 2)
  local col = math.floor((width - win_width) / 2)

  -- Crear ventana flotante
  M.state.panel_winnr = vim.api.nvim_open_win(M.state.panel_bufnr, true, {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded"
  })

  -- Configurar opciones de la ventana
  vim.api.nvim_win_set_option(M.state.panel_winnr, "wrap", true)
  vim.api.nvim_win_set_option(M.state.panel_winnr, "cursorline", true)

  -- Actualizar contenido y configurar mapeos
  update_panel_content(M.state.preview_items, M.state.selected_indices)
  setup_panel_keymaps()

  -- Resaltar sintaxis
  vim.cmd("setlocal syntax=markdown")
end

return M