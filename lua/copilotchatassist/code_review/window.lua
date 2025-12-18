-- Módulo para visualización de comentarios de Code Review en ventanas de Neovim
-- Reutiliza conceptos del módulo patches/window.lua

local M = {}
local log = require("copilotchatassist.utils.log")
local i18n = require("copilotchatassist.i18n")
local options = require("copilotchatassist.options")
local api = vim.api

-- Estado del módulo
M.state = {
  comments = {},        -- Lista de comentarios
  window = nil,         -- Info de ventana actual
  selected_comment = nil, -- ID del comentario seleccionado
  filter = {            -- Filtros actuales
    classification = nil,
    severity = nil,
    status = nil,
    file = nil
  }
}

-- Obtener color Vim para la severidad
local function get_severity_highlight(severity)
  local severity_highlights = {
    ["Baja"] = "CodeReviewLow",
    ["Media"] = "CodeReviewMedium",
    ["Alta"] = "CodeReviewHigh",
    ["Crítica"] = "CodeReviewCritical",
    -- Equivalentes en inglés
    ["Low"] = "CodeReviewLow",
    ["Medium"] = "CodeReviewMedium",
    ["High"] = "CodeReviewHigh",
    ["Critical"] = "CodeReviewCritical",
  }

  return severity_highlights[severity] or "Normal"
end

-- Obtener icono para el estado
local function get_status_icon(status)
  local status_icons = {
    ["Abierto"] = "○",
    ["Modificado"] = "◐",
    ["Retornado"] = "◁",
    ["Solucionado"] = "●",
    -- Equivalentes en inglés
    ["Open"] = "○",
    ["Modified"] = "◐",
    ["Returned"] = "◁",
    ["Resolved"] = "●",
  }

  return status_icons[status] or "○"
end

-- Obtener icono para la clasificación
local function get_classification_icon(classification)
  local classification_icons = {
    ["Estético"] = "◆",
    ["Claridad"] = "◈",
    ["Funcionalidad"] = "⬢",
    ["Bug"] = "⬟",
    ["Performance"] = "⯁",
    ["Seguridad"] = "⯃",
    ["Mantenibilidad"] = "⬣",
    -- Equivalentes en inglés
    ["Aesthetic"] = "◆",
    ["Clarity"] = "◈",
    ["Functionality"] = "⬢",
    ["Bug"] = "⬟",
    ["Performance"] = "⯁",
    ["Security"] = "⯃",
    ["Maintainability"] = "⬣",
  }

  return classification_icons[classification] or "◆"
end

-- Obtener icono para la severidad
local function get_severity_icon(severity)
  local severity_icons = {
    ["Baja"] = "•",
    ["Media"] = "••",
    ["Alta"] = "•••",
    ["Crítica"] = "!",
    -- Equivalentes en inglés
    ["Low"] = "•",
    ["Medium"] = "••",
    ["High"] = "•••",
    ["Critical"] = "!",
  }

  return severity_icons[severity] or "•"
end

-- Genera líneas para la ventana de comentarios
local function generate_comment_lines()
  local comments = M.state.comments or {}
  local lines = {
    i18n.t("code_review.window_title") .. " (" .. #comments .. ")",
    string.rep("-", 80),
    ""
  }

  -- Aplicar filtros
  local filtered_comments = {}
  for _, comment in ipairs(comments) do
    local include = true

    if M.state.filter.classification and comment.classification ~= M.state.filter.classification then
      include = false
    end

    if M.state.filter.severity and comment.severity ~= M.state.filter.severity then
      include = false
    end

    if M.state.filter.status and comment.status ~= M.state.filter.status then
      include = false
    end

    if M.state.filter.file and comment.file ~= M.state.filter.file then
      include = false
    end

    if include then
      table.insert(filtered_comments, comment)
    end
  end

  -- Si hay filtros activos, mostrar información
  if M.state.filter.classification or M.state.filter.severity or
     M.state.filter.status or M.state.filter.file then
    local filter_info = i18n.t("code_review.filtered_by")
    local filters = {}

    if M.state.filter.classification then
      table.insert(filters, i18n.t("code_review.filter_classification") .. ": " .. M.state.filter.classification)
    end

    if M.state.filter.severity then
      table.insert(filters, i18n.t("code_review.filter_severity") .. ": " .. M.state.filter.severity)
    end

    if M.state.filter.status then
      table.insert(filters, i18n.t("code_review.filter_status") .. ": " .. M.state.filter.status)
    end

    if M.state.filter.file then
      table.insert(filters, i18n.t("code_review.filter_file") .. ": " .. M.state.filter.file)
    end

    filter_info = filter_info .. " " .. table.concat(filters, ", ")
    table.insert(lines, filter_info)
    table.insert(lines, "")
  end

  if #filtered_comments == 0 then
    table.insert(lines, i18n.t("code_review.no_comments"))
  else
    -- Definir anchos de columna constantes para mejor alineación - versión simplificada
    local col_widths = {
      tipo = 2,         -- Icono del tipo (clasificación)
      sever = 2,        -- Icono de severidad
      estado = 2,       -- Icono del estado
      archivo = 50      -- Nombre del archivo:línea (ampliado ya que eliminamos otras columnas)
    }

    -- Calcular ancho total para la línea divisoria
    local total_width = col_widths.tipo + col_widths.sever + col_widths.estado + col_widths.archivo + 10  -- 10 por los separadores y márgenes

    -- Agregar encabezados de tabla con mejor espaciado usando formatos fijos y traducciones
    local current_lang = i18n.get_current_language()
    local headers = {
      T = current_lang == "spanish" and "T" or "T", -- Tipo/Classification
      S = current_lang == "spanish" and "S" or "S", -- Severidad/Severity
      E = current_lang == "spanish" and "E" or "S", -- Estado/Status
      file_line = current_lang == "spanish" and "Archivo:Línea" or "File:Line"
    }

    local header = string.format("%-2s | %-2s | %-2s | %-50s",
      headers.T,
      headers.S,
      headers.E,
      headers.file_line
    )
    table.insert(lines, header)
    table.insert(lines, string.rep("-", total_width))

    for i, comment in ipairs(filtered_comments) do
      -- Obtener iconos para las columnas
      local status_icon = get_status_icon(comment.status)
      local classification_icon = get_classification_icon(comment.classification)
      local severity_icon = get_severity_icon(comment.severity)

      -- Formatear el nombre del archivo y línea
      local file_name = vim.fn.fnamemodify(comment.file, ":t")
      local file_line = string.format("%s:%d", file_name, comment.line)

      if #file_line > col_widths.archivo then
        file_line = file_line:sub(1, col_widths.archivo - 3) .. "..."
      end

      -- Crear línea simplificada con solo iconos y archivo:línea
      -- Nota: Guardamos el índice 'i' como metadato invisible para poder seleccionar
      local line = string.format("%-2s | %-2s | %-2s | %-50s",
        classification_icon, -- Tipo/Clasificación
        severity_icon,       -- Severidad
        status_icon,         -- Estado
        file_line            -- Archivo:Línea
      )

      -- Almacenar también la severidad y el estado para el highlighting
      line = {
        text = line,
        severity = comment.severity,
        status = comment.status
      }

      table.insert(lines, line.text)
    end

    table.insert(lines, "")
    table.insert(lines, string.rep("-", total_width))
    -- Agregar leyenda simplificada con iconos en el idioma correcto
    local current_lang = i18n.get_current_language()
    table.insert(lines, "")
    table.insert(lines, current_lang == "spanish" and "Leyenda:" or "Legend:")

    -- Textos y términos según el idioma
    local texts = {
      -- T: Tipos (clasificación)
      type_header = current_lang == "spanish" and "T: Tipo - " or "T: Type - ",
      -- Clasificación/Classification
      aesthetic = current_lang == "spanish" and "Estético" or "Aesthetic",
      clarity = current_lang == "spanish" and "Claridad" or "Clarity",
      functionality = current_lang == "spanish" and "Funcionalidad" or "Functionality",
      bug = "Bug",  -- Igual en ambos idiomas
      performance = "Performance",  -- Igual en ambos idiomas
      security = current_lang == "spanish" and "Seguridad" or "Security",
      maintainability = current_lang == "spanish" and "Mantenibilidad" or "Maintainability",

      -- S: Severidad/Severity
      severity_header = current_lang == "spanish" and "S: Severidad - " or "S: Severity - ",
      low = current_lang == "spanish" and "Baja" or "Low",
      medium = current_lang == "spanish" and "Media" or "Medium",
      high = current_lang == "spanish" and "Alta" or "High",
      critical = current_lang == "spanish" and "Crítica" or "Critical",

      -- E: Estado/Status
      status_header = current_lang == "spanish" and "E: Estado - " or "S: Status - ",
      open = current_lang == "spanish" and "Abierto" or "Open",
      modified = current_lang == "spanish" and "Modificado" or "Modified",
      returned = current_lang == "spanish" and "Retornado" or "Returned",
      resolved = current_lang == "spanish" and "Solucionado" or "Resolved",
    }

    -- T: Tipos (clasificación)
    table.insert(lines, "  " .. texts.type_header ..
      "◆=" .. texts.aesthetic .. ", " ..
      "◈=" .. texts.clarity .. ", " ..
      "⬢=" .. texts.functionality .. ", " ..
      "⬟=" .. texts.bug .. ", " ..
      "⯁=" .. texts.performance .. ", " ..
      "⯃=" .. texts.security .. ", " ..
      "⬣=" .. texts.maintainability)

    -- S: Severidad
    table.insert(lines, "  " .. texts.severity_header ..
      "•=" .. texts.low .. ", " ..
      "••=" .. texts.medium .. ", " ..
      "•••=" .. texts.high .. ", " ..
      "!=" .. texts.critical)

    -- E: Estado
    table.insert(lines, "  " .. texts.status_header ..
      "○=" .. texts.open .. ", " ..
      "◐=" .. texts.modified .. ", " ..
      "◁=" .. texts.returned .. ", " ..
      "●=" .. texts.resolved)

    table.insert(lines, "")
    table.insert(lines, current_lang == "spanish" and "Presiona <Enter> sobre un comentario para ver detalles completos." or "Press <Enter> on a comment to see full details.")
  end

  return lines, filtered_comments
end

-- Mostrar tooltip con detalles del comentario
local tooltip_win = nil
local tooltip_buf = nil
local tooltip_timer = nil

-- Función para mostrar tooltip
function M.show_tooltip(comment, cursor_pos)
  -- Si ya hay un tooltip, cerrarlo
  M.close_tooltip()

  -- Si no hay comentario, no hacer nada
  if not comment then return end

  -- Crear buffer para tooltip
  tooltip_buf = vim.api.nvim_create_buf(false, true)

  -- Crear contenido del tooltip
  local lines = {
    string.format("%s: %s", i18n.t("code_review.detail_file"), vim.fn.fnamemodify(comment.file, ":t")),
    string.format("%s: %d", i18n.t("code_review.detail_line"), comment.line),
    string.format("%s: %s", i18n.t("code_review.detail_classification"), comment.classification),
    string.format("%s: %s", i18n.t("code_review.detail_severity"), comment.severity),
    string.format("%s: %s", i18n.t("code_review.detail_status"), comment.status),
    "",
    -- Añadir fragmento de código truncado
    string.format("%s:", i18n.t("code_review.detail_code_context")),
    "```",
  }

  -- Añadir contexto de código (limitado a 3 líneas)
  local code_lines = {}
  for line in (comment.code_snippet or ""):gmatch("[^\r\n]+") do
    table.insert(code_lines, line)
  end

  -- Limitar a máximo 3 líneas de código
  for i = 1, math.min(#code_lines, 3) do
    table.insert(lines, code_lines[i])
  end

  -- Si hay más líneas, indicarlo
  if #code_lines > 3 then
    table.insert(lines, "...")
  end

  table.insert(lines, "```")
  table.insert(lines, "")

  -- Añadir comentario (primera línea o limitado)
  table.insert(lines, string.format("%s:", i18n.t("code_review.detail_comment")))
  local comment_lines = {}
  for line in (comment.comment or ""):gmatch("[^\r\n]+") do
    table.insert(comment_lines, line)
  end

  -- Limitar a máximo 3 líneas de comentario
  for i = 1, math.min(#comment_lines, 3) do
    table.insert(lines, comment_lines[i])
  end

  -- Si hay más líneas, indicarlo
  if #comment_lines > 3 then
    table.insert(lines, "...")
  end

  -- Añadir la línea de ver más detalles
  table.insert(lines, "")
  local current_lang = i18n.get_current_language()
  table.insert(lines, current_lang == "spanish" and "<Enter> para ver detalles completos" or "<Enter> to see full details")

  -- Establecer contenido
  vim.api.nvim_buf_set_lines(tooltip_buf, 0, -1, false, lines)

  -- Configurar buffer
  vim.api.nvim_buf_set_option(tooltip_buf, "modifiable", false)
  vim.api.nvim_buf_set_option(tooltip_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(tooltip_buf, "filetype", "markdown")

  -- Calcular dimensiones y posición
  local width = 60
  local height = #lines

  -- Mostrar ventana flotante cerca del cursor, pero sin cubrir demasiado texto
  local row = cursor_pos.row + 1
  local col = cursor_pos.col

  -- Ajustar para no salirse de la pantalla
  if row + height > vim.o.lines - 4 then
    row = math.max(1, cursor_pos.row - height - 1)
  end

  if col + width > vim.o.columns - 4 then
    col = math.max(0, vim.o.columns - width - 4)
  end

  -- Crear ventana flotante
  tooltip_win = vim.api.nvim_open_win(tooltip_buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  -- Aplicar highlighting para markdown
  vim.api.nvim_win_set_option(tooltip_win, "winhl", "Normal:NormalFloat")

  -- Configurar autocierre al mover el cursor
  vim.api.nvim_create_autocmd({"CursorMoved", "BufLeave", "BufWinLeave"}, {
    buffer = M.state.window and M.state.window.buf,
    callback = function()
      -- Usar un timer para permitir que el cursor se mueva un poco sin cerrar inmediatamente
      if tooltip_timer then
        vim.loop.timer_stop(tooltip_timer)
        tooltip_timer = nil
      end

      tooltip_timer = vim.loop.new_timer()
      tooltip_timer:start(500, 0, vim.schedule_wrap(function()
        M.close_tooltip()
        tooltip_timer = nil
      end))
    end,
    once = true
  })

  return tooltip_win
end

-- Cerrar tooltip si está abierto
function M.close_tooltip()
  if tooltip_win and vim.api.nvim_win_is_valid(tooltip_win) then
    vim.api.nvim_win_close(tooltip_win, true)
    tooltip_win = nil
  end

  if tooltip_buf and vim.api.nvim_buf_is_valid(tooltip_buf) then
    vim.api.nvim_buf_delete(tooltip_buf, {force = true})
    tooltip_buf = nil
  end
end

-- Obtener comentario de la línea actual
function M.get_comment_at_cursor()
  if not M.state.window or not M.state.window.filtered_comments then
    return nil
  end

  local line = vim.fn.line(".")

  -- Identificar índice del comentario basado en la línea actual
  -- El encabezado tiene un título, una línea separadora, una línea en blanco y un encabezado de tabla
  local header_lines = 4

  -- Calcular el índice basado en la posición en la ventana
  local comment_index = line - header_lines

  -- Verificar que el índice es válido
  if comment_index < 1 or comment_index > #M.state.window.filtered_comments then
    return nil
  end

  return M.state.window.filtered_comments[comment_index]
end

-- Configurar keymaps para la ventana de comentarios
local function setup_keymaps(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

  -- Definir mappings locales
  local function set_keymap(mode, key, action)
    vim.api.nvim_buf_set_keymap(bufnr, mode, key, action, { noremap = true, silent = true })
  end

  -- Cerrar ventana
  set_keymap("n", "q", ":lua require'copilotchatassist.code_review.window'.close_window()<CR>")

  -- Ver detalles del comentario
  set_keymap("n", "<CR>", ":lua require'copilotchatassist.code_review.window'.show_comment_details()<CR>")

  -- Cambiar estado del comentario
  set_keymap("n", "s", ":lua require'copilotchatassist.code_review.window'.change_comment_status()<CR>")

  -- Ir al archivo y línea del comentario
  set_keymap("n", "g", ":lua require'copilotchatassist.code_review.window'.goto_comment_location()<CR>")

  -- Aplicar filtros
  set_keymap("n", "f", ":lua require'copilotchatassist.code_review.window'.apply_filter()<CR>")

  -- Limpiar filtros
  set_keymap("n", "c", ":lua require'copilotchatassist.code_review.window'.clear_filters()<CR>")

  -- Refrescar vista
  set_keymap("n", "r", ":lua require'copilotchatassist.code_review.window'.refresh_window()<CR>")

  -- Ayuda
  set_keymap("n", "?", ":lua require'copilotchatassist.code_review.window'.show_help()<CR>")

  -- Configurar evento de CursorHold para mostrar tooltip
  vim.api.nvim_create_autocmd({"CursorHold"}, {
    buffer = bufnr,
    callback = function()
      local comment = M.get_comment_at_cursor()
      if comment then
        -- Obtener posición del cursor
        local cursor_pos = {
          row = vim.fn.winline() + vim.fn.winheight(0),
          col = vim.fn.wincol()
        }
        -- Mostrar tooltip
        M.show_tooltip(comment, cursor_pos)
      end
    end
  })

  -- Configurar updatetime para controlar la velocidad de respuesta del tooltip
  local old_updatetime = vim.o.updatetime
  vim.api.nvim_buf_set_var(bufnr, "old_updatetime", old_updatetime)
  vim.o.updatetime = 800 -- 800ms para mostrar tooltip

  -- Restaurar updatetime al salir del buffer
  vim.api.nvim_create_autocmd({"BufLeave", "BufWinLeave"}, {
    buffer = bufnr,
    callback = function()
      local saved_updatetime = vim.api.nvim_buf_get_var(bufnr, "old_updatetime")
      vim.o.updatetime = saved_updatetime
    end
  })
end

-- Mostrar ventana principal de comentarios
function M.show_review_window(comments)
  M.state.comments = comments or {}

  log.debug(i18n.t("code_review.opening_window"))

  -- Generar líneas para mostrar
  local lines, filtered_comments = generate_comment_lines()

  -- Crear buffer
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Configuración del buffer
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "swapfile", false)
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "filetype", "copilotcodereview")

  -- Determinar altura de la ventana split (30% o mínimo 15 líneas)
  local height = math.max(15, math.floor(vim.o.lines * 0.3))

  -- Determinar la orientación de la ventana desde la configuración
  local opts = options.get()
  local orientation = opts.code_review_window_orientation
  if orientation == nil then
    orientation = "vertical"
    -- Actualizar la opción para futuras referencias
    options.set({code_review_window_orientation = orientation})
  end

  local width = opts.code_review_window_width or 50

  -- Crear ventana split con la orientación configurada
  if orientation == "vertical" then
    vim.cmd("botright " .. width .. "vsplit")
  else
    vim.cmd("botright " .. height .. "split")
  end

  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)

  -- Guardar referencia a ventana y buffer
  M.state.window = {
    win = win,
    buf = buf,
    filtered_comments = filtered_comments
  }

  -- Configurar keymaps
  setup_keymaps(buf)

  -- Configurar syntax highlighting
  add_syntax_highlighting(buf)

  log.debug(i18n.t("code_review.window_opened"))
  return buf
end

-- Añadir highlighting para la ventana de comentarios
function add_syntax_highlighting(buf)
  -- Crear namespace
  local ns_id = api.nvim_create_namespace("copilotcodereview")

  -- Definir destacados de colores para los iconos
  -- Asegurarnos que los colores están definidos
  vim.cmd([[hi def link CodeReviewCritical ErrorMsg]])
  vim.cmd([[hi def link CodeReviewHigh WarningMsg]])
  vim.cmd([[hi def link CodeReviewMedium String]])
  vim.cmd([[hi def link CodeReviewLow Comment]])

  vim.cmd([[hi def link CodeReviewOpen Comment]])
  vim.cmd([[hi def link CodeReviewModified String]])
  vim.cmd([[hi def link CodeReviewReturned WarningMsg]])
  vim.cmd([[hi def link CodeReviewResolved Special]])

  -- Limpiar highlighting existente
  api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  -- Obtener líneas del buffer
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Aplicar highlighting
  for i, line in ipairs(lines) do
    -- Título
    if i == 1 then
      api.nvim_buf_add_highlight(buf, ns_id, "Title", i-1, 0, -1)
    -- Separador
    elseif line:match("^%-%-%-+") then
      api.nvim_buf_add_highlight(buf, ns_id, "NonText", i-1, 0, -1)
    -- Filtros activos
    elseif line:match(i18n.t("code_review.filtered_by")) then
      api.nvim_buf_add_highlight(buf, ns_id, "Special", i-1, 0, -1)
    -- Encabezado de tabla
    elseif line:match("^ID%s+|") or line:match("^%-%-") then
      api.nvim_buf_add_highlight(buf, ns_id, "Title", i-1, 0, -1)
    -- Leyenda
    elseif line:match("^Leyenda:") or line:match("^Legend:") then
      api.nvim_buf_add_highlight(buf, ns_id, "Title", i-1, 0, -1)
    elseif line:match("^%s+T: ") or line:match("^%s+S: ") or line:match("^%s+E: ") then
      api.nvim_buf_add_highlight(buf, ns_id, "Comment", i-1, 0, -1)
    elseif line:match("Presiona <Enter>") or line:match("Press <Enter>") then
      api.nvim_buf_add_highlight(buf, ns_id, "SpecialComment", i-1, 0, -1)
    -- Línea de comentario con iconos
    elseif line:match("%S") and line:match("|") then
      -- Obtener partes de la línea
      local parts = {}
      for part in line:gmatch("[^|]+") do
        table.insert(parts, part)
      end

      if #parts >= 4 then
        -- Encontrar posiciones para destacar
        local offset = 0

        -- Tipo/Clasificación (columna 1) - Primera columna del formato
        local tipo_start = 0
        local tipo_end = parts[1]:len()
        api.nvim_buf_add_highlight(buf, ns_id, "Function", i-1, tipo_start, tipo_end)
        offset = tipo_end + 3 -- " | "

        -- Severidad (columna 2) - con colores según la severidad
        local sev_start = offset
        local sev_end = sev_start + parts[2]:len()

        -- Determinar el color según el icono de severidad
        local sev_color = "CodeReviewLow" -- Por defecto
        if parts[2]:match("!") then
          sev_color = "CodeReviewCritical"
        elseif parts[2]:match("%.•+") then
          -- Usamos un patrón genérico para evitar problemas con unicode
          local dots = parts[2]:gsub("%s+", "")
          if #dots == 3 then
            sev_color = "CodeReviewHigh"
          elseif #dots == 2 then
            sev_color = "CodeReviewMedium"
          end
        end

        api.nvim_buf_add_highlight(buf, ns_id, sev_color, i-1, sev_start, sev_end)
        offset = sev_end + 3

        -- Estado (columna 3) - con colores según el estado
        local estado_start = offset
        local estado_end = estado_start + parts[3]:len()

        -- Determinar el color según el icono de estado
        local status_color = "CodeReviewOpen" -- Por defecto
        -- Usamos condiciones simples para evitar problemas con escape sequences
        local status_text = parts[3]:gsub("%s+", "")
        if status_text == "●" then
          status_color = "CodeReviewResolved"
        elseif status_text == "◐" then
          status_color = "CodeReviewModified"
        elseif status_text == "◁" then
          status_color = "CodeReviewReturned"
        end

        api.nvim_buf_add_highlight(buf, ns_id, status_color, i-1, estado_start, estado_end)
        offset = estado_end + 3

        -- Archivo:Línea (columna 4)
        local file_start = offset
        api.nvim_buf_add_highlight(buf, ns_id, "Directory", i-1, file_start, -1)
      end
    end
  end
end

-- Cerrar ventana de comentarios
function M.close_window()
  -- Cerrar tooltip primero si está abierto
  M.close_tooltip()

  if M.state.window and M.state.window.win and api.nvim_win_is_valid(M.state.window.win) then
    api.nvim_win_close(M.state.window.win, true)
    M.state.window = nil
    log.debug(i18n.t("code_review.window_closed"))
  end
end

-- Refrescar contenido de la ventana
function M.refresh_window()
  -- Cerrar tooltip primero si está abierto
  M.close_tooltip()

  if not M.state.window or not api.nvim_win_is_valid(M.state.window.win) then
    log.warn(i18n.t("code_review.window_invalid"))
    return
  end

  local bufnr = M.state.window.buf
  if not api.nvim_buf_is_valid(bufnr) then
    log.warn(i18n.t("code_review.buffer_invalid"))
    return
  end

  -- Generar líneas actualizadas
  local lines, filtered_comments = generate_comment_lines()

  -- Actualizar ventana
  api.nvim_buf_set_option(bufnr, "modifiable", true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  api.nvim_buf_set_option(bufnr, "modifiable", false)

  -- Actualizar lista de comentarios filtrados
  M.state.window.filtered_comments = filtered_comments

  -- Actualizar highlighting
  add_syntax_highlighting(bufnr)

  log.debug(i18n.t("code_review.window_refreshed"))
end

-- Mostrar detalles de un comentario
function M.show_comment_details()
  -- Obtener línea actual
  local line = vim.fn.line(".")

  -- Buscar el comentario correspondiente a esta línea
  if not M.state.window or not M.state.window.filtered_comments then
    return
  end

  -- Identificar índice del comentario basado en la línea actual
  -- El encabezado tiene un título, una línea separadora, una línea en blanco y un encabezado de tabla
  local header_lines = 4

  -- Calcular el índice basado en la posición en la ventana
  local comment_index = line - header_lines

  if comment_index < 1 or comment_index > #M.state.window.filtered_comments then
    return
  end

  local comment = M.state.window.filtered_comments[comment_index]
  M.state.selected_comment = comment

  -- Crear líneas para mostrar detalles con mejor formato
  local detail_lines = {
    i18n.t("code_review.comment_details"),
    string.rep("-", 80),
    "",
    -- Formato más consistente con etiquetas alineadas
    i18n.t("code_review.detail_file") .. ": " .. comment.file,
    i18n.t("code_review.detail_line") .. ": " .. comment.line,
    i18n.t("code_review.detail_classification") .. ": " .. comment.classification,
    i18n.t("code_review.detail_severity") .. ": " .. comment.severity,
    i18n.t("code_review.detail_status") .. ": " .. comment.status,
    "",
    i18n.t("code_review.detail_code_context") .. ":",
    "```",
  }

  -- Añadir contexto de código
  for line in (comment.code_context or ""):gmatch("[^\r\n]+") do
    table.insert(detail_lines, line)
  end

  table.insert(detail_lines, "```")
  table.insert(detail_lines, "")
  table.insert(detail_lines, i18n.t("code_review.detail_comment") .. ":")

  -- Añadir comentario (preservar formato)
  for line in (comment.comment or ""):gmatch("[^\r\n]+") do
    table.insert(detail_lines, line)
  end

  table.insert(detail_lines, "")
  table.insert(detail_lines, i18n.t("code_review.detail_actions") .. ":")
  table.insert(detail_lines, "  [s] " .. i18n.t("code_review.action_change_status"))
  table.insert(detail_lines, "  [g] " .. i18n.t("code_review.action_goto_location"))
  table.insert(detail_lines, "  [q/Esc] " .. i18n.t("code_review.action_close"))

  -- Crear buffer para detalles
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, detail_lines)
  api.nvim_buf_set_option(buf, "modifiable", false)
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Calcular dimensiones
  local width = math.min(80, vim.o.columns - 10)
  local height = math.min(#detail_lines + 2, vim.o.lines - 4)

  -- Mostrar ventana flotante
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = i18n.t("code_review.comment_details"),
    title_pos = "center"
  })

  -- Configurar keymaps
  local function set_keymap(mode, key, action)
    api.nvim_buf_set_keymap(buf, mode, key, action, { noremap = true, silent = true })
  end

  -- Cerrar ventana
  set_keymap("n", "q", ":close<CR>")
  set_keymap("n", "<Esc>", ":close<CR>")

  -- Cambiar estado
  set_keymap("n", "s", ":lua require'copilotchatassist.code_review.window'.change_comment_status_from_details()<CR>")

  -- Ir a ubicación
  set_keymap("n", "g", ":lua require'copilotchatassist.code_review.window'.goto_comment_location_from_details()<CR>")

  log.debug(i18n.t("code_review.showing_comment_details"))
  return buf
end

-- Cambiar estado de un comentario desde la vista principal
function M.change_comment_status()
  -- Obtener comentario seleccionado
  local line = vim.fn.line(".")

  -- Buscar el comentario correspondiente a esta línea
  if not M.state.window or not M.state.window.filtered_comments then
    return
  end

  -- Identificar índice del comentario basado en la posición de la línea
  local header_lines = 4 -- Título, línea separadora, línea en blanco, encabezado de tabla

  -- Calcular índice basado en la posición en la ventana
  local comment_index = line - header_lines

  -- Verificar que el índice es válido
  if comment_index < 1 or comment_index > #M.state.window.filtered_comments then
    return
  end

  local comment = M.state.window.filtered_comments[comment_index]
  M.state.selected_comment = comment

  -- Obtener lista de estados posibles
  local code_review = require("copilotchatassist.code_review")
  local status_types = {}

  -- Traducir según idioma actual
  local lang = i18n.get_current_language()
  if lang == "english" then
    status_types = {"Open", "Modified", "Returned", "Resolved"}
  else
    status_types = {"Abierto", "Modificado", "Retornado", "Solucionado"}
  end

  -- Mostrar selector de estado
  vim.ui.select(status_types, {
    prompt = i18n.t("code_review.select_status"),
    format_item = function(item)
      if item == comment.status then
        return item .. " (current)"
      else
        return item
      end
    end
  }, function(choice)
    if choice and choice ~= comment.status then
      -- Actualizar estado
      code_review.update_comment_status(comment.id, choice)

      -- Actualizar en la lista local
      for i, c in ipairs(M.state.comments) do
        if c.id == comment.id then
          M.state.comments[i].status = choice
          break
        end
      end

      -- Refrescar ventana
      M.refresh_window()

      vim.notify(i18n.t("code_review.status_updated"), vim.log.levels.INFO)
    end
  end)
end

-- Cambiar estado de un comentario desde la vista de detalles
function M.change_comment_status_from_details()
  if not M.state.selected_comment then
    return
  end

  -- Obtener lista de estados posibles
  local code_review = require("copilotchatassist.code_review")
  local status_types = {}

  -- Traducir según idioma actual
  local lang = i18n.get_current_language()
  if lang == "english" then
    status_types = {"Open", "Modified", "Returned", "Resolved"}
  else
    status_types = {"Abierto", "Modificado", "Retornado", "Solucionado"}
  end

  -- Mostrar selector de estado
  vim.ui.select(status_types, {
    prompt = i18n.t("code_review.select_status"),
    format_item = function(item)
      if item == M.state.selected_comment.status then
        return item .. " (current)"
      else
        return item
      end
    end
  }, function(choice)
    if choice and choice ~= M.state.selected_comment.status then
      -- Actualizar estado
      local comment_id = M.state.selected_comment.id
      code_review.update_comment_status(comment_id, choice)

      -- Actualizar en la lista local
      for i, c in ipairs(M.state.comments) do
        if c.id == comment_id then
          M.state.comments[i].status = choice
          M.state.selected_comment.status = choice
          break
        end
      end

      -- Cerrar ventana de detalles
      vim.cmd("close")

      -- Refrescar ventana principal
      M.refresh_window()

      vim.notify(i18n.t("code_review.status_updated"), vim.log.levels.INFO)
    end
  end)
end

-- Ir a la ubicación del comentario seleccionado
function M.goto_comment_location()
  -- Obtener comentario seleccionado
  local line = vim.fn.line(".")

  -- Buscar el comentario correspondiente a esta línea
  if not M.state.window or not M.state.window.filtered_comments then
    return
  end

  -- Identificar índice del comentario basado en la posición de la línea
  local header_lines = 4 -- Título, línea separadora, línea en blanco, encabezado de tabla

  -- Calcular índice basado en la posición en la ventana
  local comment_index = line - header_lines

  -- Verificar que el índice es válido
  if comment_index < 1 or comment_index > #M.state.window.filtered_comments then
    return
  end

  local comment = M.state.window.filtered_comments[comment_index]

  -- Ir al archivo y línea
  local file_path = comment.file
  local line_number = comment.line

  -- Verificar si el archivo existe
  if vim.fn.filereadable(file_path) ~= 1 then
    vim.notify(i18n.t("code_review.file_not_found", {file_path}), vim.log.levels.ERROR)
    return
  end

  -- Verificar configuración para mantener la ventana abierta
  local opts = options.get()
  local keep_window_open = opts.code_review_keep_window_open
  if keep_window_open == nil then
    keep_window_open = true
    -- Actualizar la opción para futuras referencias
    options.set({code_review_keep_window_open = keep_window_open})
  end

  -- Guardar la ventana actual (ventana de comentarios)
  local comments_win = api.nvim_get_current_win()

  -- Encontrar o crear una ventana para el código
  local code_win = nil

  if keep_window_open then
    -- Asegurarse de que la ventana de comentarios es válida
    if not api.nvim_win_is_valid(comments_win) then
      -- Si la ventana no es válida, usar comportamiento original
      M.close_window()
      vim.cmd("edit " .. vim.fn.fnameescape(file_path))
      vim.cmd(":" .. line_number)
      vim.cmd("normal! zz")  -- Centrar la vista
      return
    end

    -- Buscar ventana existente que no sea la de comentarios
    for _, win in ipairs(api.nvim_list_wins()) do
      if win ~= comments_win and api.nvim_win_is_valid(win) then
        -- Asegurarse de que la ventana tiene un buffer válido
        local buf = api.nvim_win_get_buf(win)
        if api.nvim_buf_is_valid(buf) then
          code_win = win
          break
        end
      end
    end

    -- Si no encontramos una ventana válida, crear una nueva
    if not code_win then
      -- Guardar la ventana actual para volver a ella después
      local current_win = api.nvim_get_current_win()

      -- Crear una nueva ventana con split
      if options.get().code_review_window_orientation == "vertical" then
        vim.cmd("vsplit") -- Split vertical
      else
        vim.cmd("split")  -- Split horizontal
      end

      code_win = api.nvim_get_current_win()

      -- Volver a la ventana original
      if api.nvim_win_is_valid(current_win) then
        api.nvim_set_current_win(current_win)
      end
    else
      api.nvim_set_current_win(code_win)
    end

    -- Abrir el archivo en la ventana seleccionada
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    vim.cmd(":" .. line_number)
    vim.cmd("normal! zz")  -- Centrar la vista

    -- Destacar la línea
    local buf = api.nvim_get_current_buf()
    local ns_id = api.nvim_create_namespace("codereview_goto")

    api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    api.nvim_buf_add_highlight(buf, ns_id, "Search", line_number - 1, 0, -1)

    -- Limpiar el highlight después de un tiempo
    vim.defer_fn(function()
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      end
    end, 2000)

    -- Volver a la ventana de comentarios
    api.nvim_set_current_win(comments_win)
  else
    -- Comportamiento original: cerrar ventana de comentarios
    M.close_window()

    -- Abrir archivo en la línea correspondiente
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    vim.cmd(":" .. line_number)
    vim.cmd("normal! zz")  -- Centrar la vista

    -- Destacar la línea
    local buf = api.nvim_get_current_buf()
    local ns_id = api.nvim_create_namespace("codereview_goto")

    api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    api.nvim_buf_add_highlight(buf, ns_id, "Search", line_number - 1, 0, -1)

    -- Limpiar el highlight después de un tiempo
    vim.defer_fn(function()
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      end
    end, 2000)
  end

  log.debug(i18n.t("code_review.went_to_location", {file_path, line_number}))

  log.debug(i18n.t("code_review.went_to_location", {file_path, line_number}))
end

-- Ir a la ubicación desde la vista de detalles
function M.goto_comment_location_from_details()
  if not M.state.selected_comment then
    return
  end

  local comment = M.state.selected_comment

  -- Ir al archivo y línea
  local file_path = comment.file
  local line_number = comment.line

  -- Verificar si el archivo existe
  if vim.fn.filereadable(file_path) ~= 1 then
    vim.notify(i18n.t("code_review.file_not_found", {file_path}), vim.log.levels.ERROR)
    return
  end

  -- Cerrar ventana de detalles
  vim.cmd("close")

  -- Verificar configuración para mantener la ventana abierta
  local opts = options.get()
  local keep_window_open = opts.code_review_keep_window_open
  if keep_window_open == nil then
    keep_window_open = true
    -- Actualizar la opción para futuras referencias
    options.set({code_review_keep_window_open = keep_window_open})
  end

  if keep_window_open then
    -- Guardar la ventana actual
    local comments_win = M.state.window.win

    if api.nvim_win_is_valid(comments_win) then
      -- Buscar ventana existente que no sea la de comentarios
      local code_win = nil
      for _, win in ipairs(api.nvim_list_wins()) do
        if win ~= comments_win and api.nvim_win_is_valid(win) then
          -- Asegurarse de que la ventana tiene un buffer válido
          local buf = api.nvim_win_get_buf(win)
          if api.nvim_buf_is_valid(buf) then
            code_win = win
            break
          end
        end
      end

      -- Si no encontramos una ventana válida, crear una nueva
      if not code_win then
        -- Guardar la ventana actual para volver a ella después
        local current_win = api.nvim_get_current_win()

        -- Crear una nueva ventana con split
        if options.get().code_review_window_orientation == "vertical" then
          vim.cmd("vsplit") -- Split vertical
        else
          vim.cmd("split")  -- Split horizontal
        end

        code_win = api.nvim_get_current_win()
      else
        api.nvim_set_current_win(code_win)
      end

      -- Abrir el archivo en la ventana seleccionada
      vim.cmd("edit " .. vim.fn.fnameescape(file_path))
      vim.cmd(":" .. line_number)
      vim.cmd("normal! zz")  -- Centrar la vista

      -- Destacar la línea
      local buf = api.nvim_get_current_buf()
      local ns_id = api.nvim_create_namespace("codereview_goto")

      api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      api.nvim_buf_add_highlight(buf, ns_id, "Search", line_number - 1, 0, -1)

      -- Limpiar el highlight después de un tiempo
      vim.defer_fn(function()
        if api.nvim_buf_is_valid(buf) then
          api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
        end
      end, 2000)

      -- Volver a la ventana de comentarios
      api.nvim_set_current_win(comments_win)
    else
      -- Si la ventana de comentarios no es válida, comportamiento normal
      -- Cerrar ventana de comentarios principal
      M.close_window()

      -- Abrir archivo en la línea correspondiente
      vim.cmd("edit " .. vim.fn.fnameescape(file_path))
      vim.cmd(":" .. line_number)
      vim.cmd("normal! zz")  -- Centrar la vista

      -- Destacar la línea
      local buf = api.nvim_get_current_buf()
      local ns_id = api.nvim_create_namespace("codereview_goto")

      api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      api.nvim_buf_add_highlight(buf, ns_id, "Search", line_number - 1, 0, -1)

      -- Limpiar el highlight después de un tiempo
      vim.defer_fn(function()
        if api.nvim_buf_is_valid(buf) then
          api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
        end
      end, 2000)
    end
  else
    -- Comportamiento original: cerrar ventana de comentarios
    M.close_window()

    -- Abrir archivo en la línea correspondiente
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    vim.cmd(":" .. line_number)
    vim.cmd("normal! zz")  -- Centrar la vista

    -- Destacar la línea
    local buf = api.nvim_get_current_buf()
    local ns_id = api.nvim_create_namespace("codereview_goto")

    api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    api.nvim_buf_add_highlight(buf, ns_id, "Search", line_number - 1, 0, -1)

    -- Limpiar el highlight después de un tiempo
    vim.defer_fn(function()
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      end
    end, 2000)
  end

  log.debug(i18n.t("code_review.went_to_location", {file_path, line_number}))
end

-- Aplicar un filtro a la vista de comentarios
function M.apply_filter()
  local filter_options = {
    i18n.t("code_review.filter_by_classification"),
    i18n.t("code_review.filter_by_severity"),
    i18n.t("code_review.filter_by_status"),
    i18n.t("code_review.filter_by_file")
  }

  vim.ui.select(filter_options, {
    prompt = i18n.t("code_review.select_filter_type")
  }, function(choice)
    if not choice then return end

    if choice == i18n.t("code_review.filter_by_classification") then
      -- Filtrar por clasificación
      local code_review = require("copilotchatassist.code_review")
      local classifications = {}

      -- Traducir según idioma actual
      local lang = i18n.get_current_language()
      if lang == "english" then
        classifications = {"Aesthetic", "Clarity", "Functionality", "Bug", "Performance", "Security", "Maintainability"}
      else
        classifications = {"Estético", "Claridad", "Funcionalidad", "Bug", "Performance", "Seguridad", "Mantenibilidad"}
      end

      vim.ui.select(classifications, {
        prompt = i18n.t("code_review.select_classification")
      }, function(classification)
        if classification then
          M.state.filter.classification = classification
          M.refresh_window()
        end
      end)
    elseif choice == i18n.t("code_review.filter_by_severity") then
      -- Filtrar por severidad
      local severities = {}

      -- Traducir según idioma actual
      local lang = i18n.get_current_language()
      if lang == "english" then
        severities = {"Low", "Medium", "High", "Critical"}
      else
        severities = {"Baja", "Media", "Alta", "Crítica"}
      end

      vim.ui.select(severities, {
        prompt = i18n.t("code_review.select_severity")
      }, function(severity)
        if severity then
          M.state.filter.severity = severity
          M.refresh_window()
        end
      end)
    elseif choice == i18n.t("code_review.filter_by_status") then
      -- Filtrar por estado
      local status_types = {}

      -- Traducir según idioma actual
      local lang = i18n.get_current_language()
      if lang == "english" then
        status_types = {"Open", "Modified", "Returned", "Resolved"}
      else
        status_types = {"Abierto", "Modificado", "Retornado", "Solucionado"}
      end

      vim.ui.select(status_types, {
        prompt = i18n.t("code_review.select_status")
      }, function(status)
        if status then
          M.state.filter.status = status
          M.refresh_window()
        end
      end)
    elseif choice == i18n.t("code_review.filter_by_file") then
      -- Filtrar por archivo
      local files = {}
      local file_map = {}

      -- Extraer lista única de archivos
      for _, comment in ipairs(M.state.comments) do
        local file = comment.file
        local short_file = vim.fn.fnamemodify(file, ":t")

        if not file_map[short_file] then
          file_map[short_file] = file
          table.insert(files, short_file)
        end
      end

      vim.ui.select(files, {
        prompt = i18n.t("code_review.select_file")
      }, function(file)
        if file then
          M.state.filter.file = file_map[file]
          M.refresh_window()
        end
      end)
    end
  end)
end

-- Limpiar todos los filtros
function M.clear_filters()
  M.state.filter = {
    classification = nil,
    severity = nil,
    status = nil,
    file = nil
  }

  M.refresh_window()
  vim.notify(i18n.t("code_review.filters_cleared"), vim.log.levels.INFO)
end

-- Mostrar ventana de estadísticas
function M.show_stats_window(stats)
  -- Crear líneas para mostrar
  local lines = {
    i18n.t("code_review.statistics_title"),
    string.rep("-", 50),
    "",
    i18n.t("code_review.total_comments") .. ": " .. stats.total,
    "",
    i18n.t("code_review.by_status") .. ":",
  }

  -- Añadir estadísticas por estado
  for status, count in pairs(stats.by_status) do
    table.insert(lines, string.format("  - %s: %d", status, count))
  end

  table.insert(lines, "")
  table.insert(lines, i18n.t("code_review.by_severity") .. ":")

  -- Añadir estadísticas por severidad
  for _, severity in ipairs({"Crítica", "Alta", "Media", "Baja"}) do
    local count = stats.by_severity[severity] or 0
    table.insert(lines, string.format("  - %s: %d", severity, count))
  end

  table.insert(lines, "")
  table.insert(lines, i18n.t("code_review.by_classification") .. ":")

  -- Añadir estadísticas por clasificación
  for classification, count in pairs(stats.by_classification) do
    if count > 0 then
      table.insert(lines, string.format("  - %s: %d", classification, count))
    end
  end

  table.insert(lines, "")
  table.insert(lines, i18n.t("code_review.by_file") .. ":")

  -- Añadir estadísticas por archivo (top 5)
  local files = {}
  for file, count in pairs(stats.by_file) do
    table.insert(files, {file = file, count = count})
  end

  -- Ordenar por cantidad descendente
  table.sort(files, function(a, b) return a.count > b.count end)

  -- Mostrar top 5 o menos
  local limit = math.min(5, #files)
  for i = 1, limit do
    local file_info = files[i]
    table.insert(lines, string.format("  - %s: %d", vim.fn.fnamemodify(file_info.file, ":t"), file_info.count))
  end

  -- Crear buffer para estadísticas
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_buf_set_option(buf, "modifiable", false)
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Calcular dimensiones
  local width = 60
  local height = #lines

  -- Mostrar ventana flotante
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = i18n.t("code_review.statistics_title"),
    title_pos = "center"
  })

  -- Configurar keymaps
  api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })

  log.debug(i18n.t("code_review.showing_statistics"))
  return buf
end

-- Mostrar ayuda
function M.show_help()
  local help_lines = {
    i18n.t("code_review.help_title"),
    string.rep("-", 50),
    "",
    i18n.t("code_review.help_main_window") .. ":",
    "",
    "q       - " .. i18n.t("code_review.help_close"),
    "<CR>    - " .. i18n.t("code_review.help_show_details"),
    "s       - " .. i18n.t("code_review.help_change_status"),
    "g       - " .. i18n.t("code_review.help_goto_location"),
    "f       - " .. i18n.t("code_review.help_apply_filter"),
    "c       - " .. i18n.t("code_review.help_clear_filters"),
    "r       - " .. i18n.t("code_review.help_refresh"),
    "?       - " .. i18n.t("code_review.help_show_help"),
    "",
    i18n.t("code_review.help_details_window") .. ":",
    "",
    "q/Esc   - " .. i18n.t("code_review.help_close"),
    "s       - " .. i18n.t("code_review.help_change_status"),
    "g       - " .. i18n.t("code_review.help_goto_location"),
  }

  -- Crear buffer para ayuda
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  api.nvim_buf_set_option(buf, "modifiable", false)
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Calcular dimensiones
  local width = 60
  local height = #help_lines

  -- Mostrar ventana flotante
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = i18n.t("code_review.help_title"),
    title_pos = "center"
  })

  -- Configurar keymaps
  api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })

  log.debug(i18n.t("code_review.showing_help"))
  return buf
end

return M