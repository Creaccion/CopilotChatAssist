-- Módulo consolidado para manejar la visualización y gestión de TODOs
-- Integra las funcionalidades de todos/init.lua y todos/window.lua

local M = {}

-- Módulo para manejar la visualización y gestión de TODOs
local uv = vim.loop
local file_utils = require("copilotchatassist.utils.file")
local context = require("copilotchatassist.context")
local options = require("copilotchatassist.options")
local utils = require("copilotchatassist.utils")
local log = require("copilotchatassist.utils.log")
local copilot_api = require("copilotchatassist.copilotchat_api")
local i18n = require("copilotchatassist.i18n")
local api = vim.api

-- Almacena el estado de la visualización de TODOs
M.state = {
  paths = nil,       -- Rutas a archivos de contexto
  todo_split = nil,  -- Información sobre la ventana split de TODOs (win, buf)
  todo_tasks = {},   -- Tareas actuales
  selected_task = nil, -- Tarea actualmente seleccionada
  selected_task_index = nil, -- Índice de la tarea seleccionada
  floating_windows = {},  -- Ventanas flotantes activas
}

-- Obtener rutas actualizadas desde el contexto
local function get_paths()
  if not M.state.paths then
    M.state.paths = context.get_context_paths()
  end
  return M.state.paths
end

-- Estandarización de iconos de estado
local status_icons = {
  -- Versiones en mayúsculas (inglés)
  ["DONE"] = "✅",
  ["TODO"] = "⬜",
  ["PENDING"] = "⬜",
  ["IN_PROGRESS"] = "🔄",
  ["IN PROGRESS"] = "🔄",

  -- Versiones en mayúsculas (español)
  ["COMPLETADO"] = "✅",
  ["PENDIENTE"] = "⬜",
  ["EN PROGRESO"] = "🔄",
  ["EN_PROGRESO"] = "🔄",

  -- Versiones con iconos
  ["✅ DONE"] = "✅",
  ["⬜ PENDING"] = "⬜",
  ["⬜ TODO"] = "⬜",
  ["✅"] = "✅",
  ["⬜"] = "⬜",

  -- Versiones en minúsculas (inglés)
  ["done"] = "✅",
  ["todo"] = "⬜",
  ["pending"] = "⬜",
  ["in_progress"] = "🔄",
  ["in progress"] = "🔄",

  -- Versiones en minúsculas (español)
  ["completado"] = "✅",
  ["pendiente"] = "⬜",
  ["en progreso"] = "🔄",
  ["en_progreso"] = "🔄",
}

-- Parsea el archivo markdown de TODOs y extrae las tareas
local function parse_todo_markdown(path)
  local tasks = {}
  local lines = {}
  local f = io.open(path, "r")
  if not f then
    log.debug({
      english = "Could not open TODO file: " .. path,
      spanish = "No se pudo abrir el archivo TODO: " .. path
    })
    return tasks
  end

  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()

  if #lines == 0 then
    log.debug({
      english = "TODO file is empty: " .. path,
      spanish = "El archivo TODO está vacío: " .. path
    })
    return tasks
  end

  -- Find table header
  local header_idx = nil
  for i, line in ipairs(lines) do
    if line:match("|") and line:lower():find("status") then
      header_idx = i
      break
    end
  end

  if not header_idx then
    log.debug({
      english = "Could not find table header in TODO file",
      spanish = "No se pudo encontrar el encabezado de la tabla en el archivo TODO"
    })
    return tasks
  end

  -- Parse rows
  for i = header_idx + 2, #lines do
    local row = lines[i]
    if not row:match("|") or row:match("^%s*<!--") then break end

    local cols = {}
    for col in row:gmatch("|([^|]*)") do
      table.insert(cols, vim.trim(col))
    end

    if #cols >= 5 then
      table.insert(tasks, {
        number = cols[1],
        status = cols[2],
        priority = cols[3],
        category = cols[4],
        title = cols[5],
        description = cols[6] or "",
        raw = row,
      })
    else
      log.debug({
        english = "Malformed TODO row: " .. row,
        spanish = "Fila de TODO mal formada: " .. row
      })
    end
  end

  log.debug({
    english = "Parsed " .. #tasks .. " tasks from TODO file",
    spanish = "Se analizaron " .. #tasks .. " tareas del archivo TODO"
  })

  return tasks
end

local function find_existing_todo_win()
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    local name = api.nvim_buf_get_name(buf)
    if name:find("TODO_") then
      return win, buf
    end
  end
  return nil, nil
end

local function extract_todo_title(lines)
  for _, line in ipairs(lines) do
    local title = line:match("^#%s*(TODO.*)")
    if title then
      return title
    end
  end
  return "TODO"
end

-- Helper: extract icon from status (first emoji or symbol)
local function extract_icon(status)
  -- Try to extract emoji/icon from status string
  local icon = status:match("[%z\1-\127\194-\244][\128-\191]*")
  if icon and (icon == "✅" or icon == "⬜" or icon == "🔄") then
    return icon
  end
  -- If no emoji, map text to icon
  return status_icons[status] or status
end

-- Actualizar la visualización de TODOs en el buffer
local function reload_todo_split(buf)
  log.debug({
    english = "reload_todo_split called",
    spanish = "reload_todo_split llamado"
  })

  -- Si se proporciona el estado de la ventana split, usar su buffer
  if M.state.todo_split and not buf then
    if not vim.api.nvim_win_is_valid(M.state.todo_split.win) then
      log.debug({
        english = "todo_split window is invalid",
        spanish = "Ventana todo_split inválida"
      })
      return
    end
    buf = M.state.todo_split.buf
  else
    -- Usar el buffer actual si no se proporciona uno
    buf = buf or vim.api.nvim_get_current_buf()
  end

  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    log.debug({
      english = "Buffer is nil or invalid",
      spanish = "Buffer es nulo o inválido"
    })
    return
  end

  local paths = get_paths()
  local todo_path = paths.todo_path
  local tasks = parse_todo_markdown(todo_path)

  -- Actualizar las tareas en el estado
  M.state.todo_tasks = tasks

  local lines = {}
  local highlights = {}

  -- Priority icons (①-⑤)
  local priority_icons = { "①", "②", "③", "④", "⑤" }

  -- Status icons para visualización
  local display_status_icons = {
    done = "[✔]",
    pending = "[ ]",
    ["in progress"] = "[~]",
    ["in_progress"] = "[~]",
    progress = "[~]",
  }

  if not tasks or #tasks == 0 then
    log.debug({
      english = "No tasks found",
      spanish = "No se encontraron tareas"
    })
    -- Usar i18n para obtener el mensaje en el idioma configurado
    local message = i18n.t("todo.no_tasks_available", {})
    if not message or message == "todo.no_tasks_available" then
      -- Si no se encuentra la traducción, usar fallback directo
      message = i18n.get_current_language() == "spanish" and "No hay tareas disponibles. Usa 'r' para actualizar." or "No tasks available. Use 'r' to refresh."
    end
    table.insert(lines, message)
  else
    for i, task in ipairs(tasks) do
      local priority = tonumber(task.priority) or 3
      if priority < 1 or priority > 5 then
        priority = 3
      end
      local priority_icon = priority_icons[priority]

      -- Determine status icon
      local status = (task.status or "pending"):lower()
      local status_icon = display_status_icons[status] or "[ ]"

      -- Compose line: <priority_icon> <status_icon> <title>
      local line = string.format("%s %s %s", priority_icon, status_icon, task.title or "")
      table.insert(lines, line)

      -- Highlight the title according to priority
      local title_start = #priority_icon + 1 + #status_icon + 1 -- spaces included
      local title_end = #line
      local hl_group = options.todo_highlights[priority] or ""
      if hl_group ~= "" then
        table.insert(highlights, {
          line = i - 1,
          col_start = title_start,
          col_end = title_end,
          group = hl_group,
        })
      end
    end
  end

  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      buf,
      -1,
      hl.group,
      hl.line,
      hl.col_start,
      hl.col_end
    )
  end

  log.debug({
    english = string.format("Rendered %d tasks, %d highlights", #lines, #highlights),
    spanish = string.format("Se renderizaron %d tareas, %d resaltados", #lines, #highlights)
  })
end

-- Crear una ventana flotante para visualización de TODOs
function M.create_floating_window(opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.8)
  local height = opts.height or math.floor(vim.o.lines * 0.8)
  local row = opts.row or math.floor((vim.o.lines - height) / 2)
  local col = opts.col or math.floor((vim.o.columns - width) / 2)
  local title = opts.title or "TODOs"
  local content = opts.content or {}
  local filetype = opts.filetype or "markdown"

  local buf = api.nvim_create_buf(false, true)

  -- Configurar buffer
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "swapfile", false)
  api.nvim_buf_set_option(buf, "filetype", filetype)

  -- Establecer contenido
  api.nvim_buf_set_lines(buf, 0, -1, false, content)

  -- Crear ventana
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  }

  local win = api.nvim_open_win(buf, true, win_opts)

  -- Guardar referencia
  local win_id = #M.state.floating_windows + 1
  M.state.floating_windows[win_id] = {
    win = win,
    buf = buf,
    opts = opts
  }

  -- Configurar keymaps
  if opts.keymaps then
    for key, action in pairs(opts.keymaps) do
      if type(action) == "function" then
        api.nvim_buf_set_keymap(buf, "n", key, "", {
          noremap = true,
          silent = true,
          callback = function()
            action(buf, win, win_id)
          end,
        })
      elseif type(action) == "string" then
        api.nvim_buf_set_keymap(buf, "n", key, action, {
          noremap = true,
          silent = true
        })
      end
    end
  end

  -- Añadir siempre mapeo para cerrar
  api.nvim_buf_set_keymap(buf, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      M.close_floating_window(win_id)
    end
  })

  -- Añadir autocomando para limpiar la referencia al cerrar la ventana
  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    callback = function()
      M.state.floating_windows[win_id] = nil
    end,
    once = true
  })

  return win_id
end

-- Actualizar contenido de ventana flotante
function M.update_window_content(win_id, content)
  local window = M.state.floating_windows[win_id]
  if not window or not api.nvim_win_is_valid(window.win) then
    return false
  end

  local buf = window.buf

  -- Actualizar contenido
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, content)
  api.nvim_buf_set_option(buf, "modifiable", false)

  return true
end

-- Cerrar ventana flotante
function M.close_floating_window(win_id)
  local window = M.state.floating_windows[win_id]
  if not window or not api.nvim_win_is_valid(window.win) then
    return false
  end

  api.nvim_win_close(window.win, true)
  M.state.floating_windows[win_id] = nil

  return true
end

function M.show_task_details(task)
  -- Asegurarnos de obtener el idioma directamente de la configuración
  local lang = options.get().language or "english"
  local labels = {}

  if lang == "spanish" then
    labels = {
      title = "Detalles de la Tarea",
      number = "Número",
      status = "Estado",
      priority = "Prioridad",
      category = "Categoría",
      task_title = "Título",
      description = "Descripción",
      actions = "Acciones",
      close = "Cerrar",
      change_status = "Cambiar Estado",
      set_priority = "Cambiar Prioridad"
    }
  else
    labels = {
      title = "Task Details",
      number = "Number",
      status = "Status",
      priority = "Priority",
      category = "Category",
      task_title = "Title",
      description = "Description",
      actions = "Actions",
      close = "Close",
      change_status = "Change Status",
      set_priority = "Change Priority"
    }
  end

  -- Get status icon
  local status_text = task.status or "pending"
  local status_icon = status_icons[status_text] or "⬜"

  -- Convert priority to visual representation
  local priority = tonumber(task.priority) or 3
  if priority < 1 or priority > 5 then priority = 3 end
  local priority_icons = { "①", "②", "③", "④", "⑤" }
  local priority_visual = priority_icons[priority] .. " (" .. priority .. "/5)"

  -- Create formatted header
  local header_line = "╭" .. string.rep("─", 58) .. "╮"
  local footer_line = "╰" .. string.rep("─", 58) .. "╯"
  local title_line = "│ " .. labels.title .. string.rep(" ", 58 - labels.title:len() - 3) .. "│"
  local separator = "├" .. string.rep("─", 58) .. "┤"

  -- Format each field with proper alignment and styling
  local function format_field(label, value, icon)
    local icon_str = icon or ""
    return "│ " .. label .. ": " .. icon_str .. " " ..
           (value or "") .. string.rep(" ", 58 - label:len() - (value or ""):len() - icon_str:len() - 4) .. "│"
  end

  -- Create lines with better formatting
  local lines = {
    header_line,
    title_line,
    separator,
    format_field(labels.number, task.number),
    format_field(labels.status, status_text, status_icon),
    format_field(labels.priority, "", priority_visual),
    format_field(labels.category, task.category),
    format_field(labels.task_title, task.title),
    separator,
    "│ " .. labels.description .. string.rep(" ", 58 - labels.description:len() - 3) .. "│",
  }

  -- Add description with word wrap
  if task.description and task.description:len() > 0 then
    local desc_width = 56  -- Allow for margin
    local wrapped_desc = {}

    for line in (task.description .. "\n"):gmatch("([^\n]*)\n") do
      -- Word wrap long lines
      while line:len() > desc_width do
        local break_pos = desc_width
        -- Find space to break line
        while break_pos > 1 and line:sub(break_pos, break_pos) ~= " " do
          break_pos = break_pos - 1
        end
        if break_pos == 1 then break_pos = desc_width end

        table.insert(wrapped_desc, "│ " .. line:sub(1, break_pos) ..
                   string.rep(" ", 58 - break_pos - 3) .. "│")
        line = line:sub(break_pos + 1)
      end

      table.insert(wrapped_desc, "│ " .. line .. string.rep(" ", 58 - line:len() - 3) .. "│")
    end

    for _, line in ipairs(wrapped_desc) do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "│ " .. string.rep(" ", 58 - 3) .. "│")
  end

  -- Add actions section
  table.insert(lines, separator)
  table.insert(lines, "│ " .. labels.actions .. string.rep(" ", 58 - labels.actions:len() - 3) .. "│")
  table.insert(lines, "│ " .. string.rep(" ", 2) .. "[s] " .. labels.change_status ..
               string.rep(" ", 58 - labels.change_status:len() - 8) .. "│")
  table.insert(lines, "│ " .. string.rep(" ", 2) .. "[P] " .. labels.set_priority ..
               string.rep(" ", 58 - labels.set_priority:len() - 8) .. "│")
  table.insert(lines, "│ " .. string.rep(" ", 2) .. "[q/Esc] " .. labels.close ..
               string.rep(" ", 58 - labels.close:len() - 12) .. "│")
  table.insert(lines, footer_line)

  -- Create buffer with improved dimensions
  local width = 60  -- Border adds padding
  local height = #lines
  local popup_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)

  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "none",  -- We're creating our own border
  }

  local popup_win = api.nvim_open_win(popup_buf, true, opts)

  -- Apply syntax highlighting for the content
  local ns_id = api.nvim_create_namespace("todo_details")

  -- Title highlighting
  api.nvim_buf_add_highlight(popup_buf, ns_id, "Title", 1, 2, 2 + labels.title:len())

  -- Field label highlighting
  for i = 3, 7 do
    local line = lines[i+1]
    local colon_pos = line:find(":")
    if colon_pos then
      api.nvim_buf_add_highlight(popup_buf, ns_id, "Label", i, 2, colon_pos)
    end
  end

  -- Priority highlighting based on value
  local hl_group = options.todo_highlights[priority] or "TodoPriority" .. priority
  local prio_line = lines[6] -- Assuming priority is line 6
  local priority_pos = prio_line:find(priority_icons[priority])
  if priority_pos then
    api.nvim_buf_add_highlight(popup_buf, ns_id, hl_group, 5, priority_pos, priority_pos + 3)
  end

  -- Status highlighting
  local status_line = lines[5] -- Assuming status is line 5
  local status_pos = status_line:find(status_icon)
  if status_pos then
    local status_hl = "TodoPending"
    if status_text:lower():find("done") or status_text:lower():find("completado") then
      status_hl = "TodoDone"
    elseif status_text:lower():find("progress") or status_text:lower():find("progreso") then
      status_hl = "TodoInProgress"
    end
    api.nvim_buf_add_highlight(popup_buf, ns_id, status_hl, 4, status_pos, status_pos + 1)
  end

  -- Description title highlighting
  api.nvim_buf_add_highlight(popup_buf, ns_id, "Label", 9, 2, 2 + labels.description:len())

  -- Actions title highlighting
  local actions_line_idx = #lines - 5
  api.nvim_buf_add_highlight(popup_buf, ns_id, "Label", actions_line_idx, 2, 2 + labels.actions:len())

  -- Keyboard shortcuts highlighting
  for i = 1, 3 do
    local shortcut_line_idx = #lines - 5 + i
    local line = lines[shortcut_line_idx]
    local open_bracket = line:find("[")
    local close_bracket = line:find("]")
    if open_bracket and close_bracket then
      api.nvim_buf_add_highlight(popup_buf, ns_id, "Special", shortcut_line_idx - 1, open_bracket, close_bracket + 1)
    end
  end

  -- Setup buffer options
  api.nvim_buf_set_option(popup_buf, "modifiable", false)
  api.nvim_buf_set_option(popup_buf, "buftype", "nofile")
  api.nvim_buf_set_option(popup_buf, "filetype", "todo_details")

  -- Setup keymaps for actions
  api.nvim_buf_set_keymap(popup_buf, "n", "<Esc>", "<cmd>bd!<CR>", { noremap = true, silent = true })
  api.nvim_buf_set_keymap(popup_buf, "n", "q", "<cmd>bd!<CR>", { noremap = true, silent = true })

  -- Add keymap for changing status
  api.nvim_buf_set_keymap(popup_buf, "n", "s", "", {
    noremap = true,
    silent = true,
    callback = function()
      -- Hide details window
      api.nvim_win_close(popup_win, true)

      -- Show status selection menu
      vim.ui.select({"pending", "in_progress", "done"}, {
        prompt = lang == "spanish" and "Cambiar estado a:" or "Change status to:"
      }, function(choice)
        if choice then
          -- Get the task index
          local task_index = M.state.selected_task_index

          -- Change the status
          if task_index then
            M.change_task_status(task_index, choice, M.state.todo_split and M.state.todo_split.buf)

            -- Show updated details
            vim.defer_fn(function()
              M.show_task_details(task)
            end, 100)
          end
        end
      end)
    end,
    desc = "Change task status",
  })

  -- Add keymap for changing priority
  api.nvim_buf_set_keymap(popup_buf, "n", "P", "", {
    noremap = true,
    silent = true,
    callback = function()
      -- Hide details window
      api.nvim_win_close(popup_win, true)

      -- Show priority selection menu
      vim.ui.select({"1", "2", "3", "4", "5"}, {
        prompt = lang == "spanish" and "Cambiar prioridad a:" or "Change priority to:"
      }, function(choice)
        if choice then
          -- Get the task index
          local task_index = M.state.selected_task_index

          -- Change the priority
          if task_index then
            M.change_task_priority(task_index, choice, M.state.todo_split and M.state.todo_split.buf)

            -- Update task's priority in memory for refreshing details
            if M.state.todo_tasks and M.state.todo_tasks[task_index] then
              M.state.todo_tasks[task_index].priority = choice
            end

            -- Show updated details with a slight delay to allow file update
            vim.defer_fn(function()
              -- Get the updated task from the refreshed state
              local updated_task = M.state.todo_tasks[task_index] or task
              M.show_task_details(updated_task)
            end, 100)
          end
        end
      end)
    end,
    desc = "Change task priority",
  })

  return popup_buf, popup_win
end

-- Filtrar tareas por estado
function M.filter_tasks_by_status(status, buf)
  if status == "all" then
    reload_todo_split(buf)
    return
  end

  local filtered_tasks = {}
  for _, task in ipairs(M.state.todo_tasks or {}) do
    local task_status = (task.status or ""):lower()
    if task_status:find(status:lower()) then
      table.insert(filtered_tasks, task)
    end
  end

  -- Obtener idioma directamente de opciones
  local lang = options.get().language or "english"
  local title = lang:lower() == "spanish"
    and ("Filtrado por estado: " .. status)
    or ("Filtered by status: " .. status)
  M.display_filtered_tasks(filtered_tasks, buf, title)
end

-- Filtrar tareas por prioridad
function M.filter_tasks_by_priority(priority, buf)
  if priority == "all" then
    reload_todo_split(buf)
    return
  end

  local filtered_tasks = {}
  local target_priority = tonumber(priority)

  for _, task in ipairs(M.state.todo_tasks or {}) do
    local task_priority = tonumber(task.priority or "3")
    if task_priority == target_priority then
      table.insert(filtered_tasks, task)
    end
  end

  -- Obtener idioma directamente de opciones
  local lang = options.get().language or "english"
  local title = lang:lower() == "spanish"
    and ("Filtrado por prioridad: " .. priority)
    or ("Filtered by priority: " .. priority)
  M.display_filtered_tasks(filtered_tasks, buf, title)
end

-- Mostrar tareas filtradas
function M.display_filtered_tasks(tasks, buf, title)
  local lines = {}
  local highlights = {}

  -- Añadir título con información del filtro
  table.insert(lines, title)
  table.insert(lines, string.rep("-", #title))

  -- Priority icons (①-⑤)
  local priority_icons = { "①", "②", "③", "④", "⑤" }

  -- Status icons para visualización
  local display_status_icons = {
    done = "[✔]",
    pending = "[ ]",
    ["in progress"] = "[~]",
    ["in_progress"] = "[~]",
    progress = "[~]",
  }

  if #tasks == 0 then
    table.insert(lines, i18n.get_current_language() == "spanish"
      and "No se encontraron tareas con este filtro."
      or "No tasks found with this filter.")
  else
    for i, task in ipairs(tasks) do
      local priority = tonumber(task.priority) or 3
      if priority < 1 or priority > 5 then
        priority = 3
      end
      local priority_icon = priority_icons[priority]

      -- Determine status icon
      local status = (task.status or "pending"):lower()
      local status_icon = display_status_icons[status] or "[ ]"

      -- Compose line: <priority_icon> <status_icon> <title>
      local line = string.format("%s %s %s", priority_icon, status_icon, task.title or "")
      table.insert(lines, line)

      -- Highlight the title according to priority
      local title_start = #priority_icon + 1 + #status_icon + 1 -- spaces included
      local title_end = #line
      local hl_group = options.todo_highlights[priority] or ""
      if hl_group ~= "" then
        table.insert(highlights, {
          line = i + 1, -- +2 for title lines
          col_start = title_start,
          col_end = title_end,
          group = hl_group,
        })
      end
    end
  end

  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      buf,
      -1,
      hl.group,
      hl.line,
      hl.col_start,
      hl.col_end
    )
  end

  -- Añadir nota sobre cómo volver a la vista completa
  log.info({
    english = "Use 'r' to return to the full view",
    spanish = "Use 'r' para volver a la vista completa"
  })
end

-- Cambiar el estado de una tarea
function M.change_task_status(task_index, new_status, buf)
  local paths = get_paths()
  local todo_path = paths.todo_path

  -- Leer el contenido actual del archivo
  local content = file_utils.read_file(todo_path) or ""
  local lines = {}
  for line in content:gmatch("[^\n]+") do
    table.insert(lines, line)
  end

  -- Parsear las tareas y encontrar la línea a modificar
  local tasks = parse_todo_markdown(todo_path)

  if task_index > 0 and task_index <= #tasks then
    local task = tasks[task_index]
    if not task or not task.raw then
      log.error({
        english = "Could not find task or incorrect format",
        spanish = "No se pudo encontrar la tarea o formato incorrecto"
      })
      return
    end

    -- Buscar la línea en el archivo original
    local header_idx = nil
    for i, line in ipairs(lines) do
      if line:match("|") and line:lower():find("status") then
        header_idx = i
        break
      end
    end

    if not header_idx or header_idx + 1 + task_index > #lines then
      log.error({
        english = "Could not find task position in the file",
        spanish = "No se pudo encontrar la posición de la tarea en el archivo"
      })
      return
    end

    -- La línea de la tarea es header_idx + separator + índice
    local line_idx = header_idx + 1 + task_index
    local line = lines[line_idx]

    -- Reemplazar el estado en la línea
    local parts = {}
    for part in line:gmatch("[^|]+") do
      table.insert(parts, part)
    end

    if #parts >= 3 then  -- Al menos necesitamos número, estado y el resto
      parts[2] = " " .. new_status .. " "  -- El formato tiene espacios alrededor
      lines[line_idx] = table.concat(parts, "|")

      -- Escribir de vuelta al archivo
      local new_content = table.concat(lines, "\n")
      file_utils.write_file(todo_path, new_content)

      log.info({
        english = "Task status updated to: " .. new_status,
        spanish = "Estado de tarea actualizado a: " .. new_status
      })

      -- Recargar la visualización
      reload_todo_split(buf)
    else
      log.error({
        english = "Incorrect line format: " .. line,
        spanish = "Formato de línea incorrecto: " .. line
      })
    end
  else
    log.error({
      english = "Task index out of range",
      spanish = "Índice de tarea fuera de rango"
    })
  end
end

-- Cambiar la prioridad de una tarea
function M.change_task_priority(task_index, new_priority, buf)
  local paths = get_paths()
  local todo_path = paths.todo_path

  -- Leer el contenido actual del archivo
  local content = file_utils.read_file(todo_path) or ""
  local lines = {}
  for line in content:gmatch("[^\n]+") do
    table.insert(lines, line)
  end

  -- Parsear las tareas y encontrar la línea a modificar
  local tasks = parse_todo_markdown(todo_path)

  if task_index > 0 and task_index <= #tasks then
    local task = tasks[task_index]
    if not task or not task.raw then
      log.error({
        english = "Could not find task or incorrect format",
        spanish = "No se pudo encontrar la tarea o formato incorrecto"
      })
      return
    end

    -- Buscar la línea en el archivo original
    local header_idx = nil
    for i, line in ipairs(lines) do
      if line:match("|") and line:lower():find("status") then
        header_idx = i
        break
      end
    end

    if not header_idx or header_idx + 1 + task_index > #lines then
      log.error({
        english = "Could not find task position in the file",
        spanish = "No se pudo encontrar la posición de la tarea en el archivo"
      })
      return
    end

    -- La línea de la tarea es header_idx + separator + índice
    local line_idx = header_idx + 1 + task_index
    local line = lines[line_idx]

    -- Reemplazar la prioridad en la línea
    local parts = {}
    for part in line:gmatch("[^|]+") do
      table.insert(parts, part)
    end

    if #parts >= 4 then  -- Necesitamos número, estado, prioridad y el resto
      parts[3] = " " .. new_priority .. " "  -- El formato tiene espacios alrededor
      lines[line_idx] = table.concat(parts, "|")

      -- Escribir de vuelta al archivo
      local new_content = table.concat(lines, "\n")
      file_utils.write_file(todo_path, new_content)

      log.info({
        english = "Task priority updated to: " .. new_priority,
        spanish = "Prioridad de tarea actualizada a: " .. new_priority
      })

      -- Recargar la visualización
      reload_todo_split(buf)
    else
      log.error({
        english = "Incorrect line format: " .. line,
        spanish = "Formato de línea incorrecto: " .. line
      })
    end
  else
    log.error({
      english = "Task index out of range",
      spanish = "Índice de tarea fuera de rango"
    })
  end
end

-- Main: open or reuse split for TODOs
function M.open_todo_split()
  local paths = get_paths()
  local todo_path = paths.todo_path

  -- Try to find existing buffer/window for this TODO
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    if api.nvim_buf_get_name(buf) == todo_path then
      api.nvim_set_current_win(win)
      reload_todo_split(buf)
      return
    end
  end

  -- Open split (vertical by default)
  local orientation = options.todo_split_orientation or "vertical"
  if orientation == "vertical" then
    vim.cmd("vsplit")
  else
    vim.cmd("split")
  end

  local bufnr = api.nvim_create_buf(false, true)
  local win = api.nvim_get_current_win()

  api.nvim_win_set_buf(win, bufnr)
  api.nvim_buf_set_name(bufnr, todo_path)

  -- Guardar referencias en el estado
  M.state.todo_split = {
    win = win,
    buf = bufnr
  }

  -- Configurar el buffer
  reload_todo_split(bufnr)
  api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  api.nvim_buf_set_option(bufnr, "swapfile", false)
  api.nvim_buf_set_option(bufnr, "modifiable", false)
  api.nvim_buf_set_option(bufnr, "readonly", true)

  -- Configurar mapeos de teclado
  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    callback = function()
      local lnum = api.nvim_win_get_cursor(0)[1]
      if M.state.todo_tasks and lnum > 0 and lnum <= #M.state.todo_tasks then
        local task = M.state.todo_tasks[lnum]
        M.state.selected_task = task
        M.state.selected_task_index = lnum
        M.show_task_details(task)
      end
    end,
    desc = "Show task details",
  })

  api.nvim_buf_set_keymap(bufnr, "n", "r", "", {
    noremap = true,
    callback = function()
      -- Usar log con traducción automática
      log.info({
        english = "Refreshing TODOs " .. todo_path,
        spanish = "Actualizando TODOs " .. todo_path
      })
      M.generate_todo(function()
        reload_todo_split(bufnr)
      end)
    end,
    desc = i18n.get_current_language() == "spanish" and "Actualizar lista de TODOs" or "Refresh TODO list",
  })

  -- Añadir mapeo para filtrar por estado
  api.nvim_buf_set_keymap(bufnr, "n", "f", "", {
    noremap = true,
    callback = function()
      vim.ui.select({"all", "pending", "in_progress", "done"}, {
        prompt = i18n.get_current_language() == "spanish" and "Filtrar por estado:" or "Filter by status:"
      }, function(choice)
        if choice then
          M.filter_tasks_by_status(choice, bufnr)
        end
      end)
    end,
    desc = "Filter tasks by status",
  })

  -- Añadir mapeo para filtrar por prioridad
  api.nvim_buf_set_keymap(bufnr, "n", "p", "", {
    noremap = true,
    callback = function()
      vim.ui.select({"all", "1", "2", "3", "4", "5"}, {
        prompt = i18n.get_current_language() == "spanish" and "Filtrar por prioridad:" or "Filter by priority:"
      }, function(choice)
        if choice then
          M.filter_tasks_by_priority(choice, bufnr)
        end
      end)
    end,
    desc = "Filter tasks by priority",
  })

  -- Añadir mapeo para cambiar el estado de una tarea
  api.nvim_buf_set_keymap(bufnr, "n", "s", "", {
    noremap = true,
    callback = function()
      local lnum = api.nvim_win_get_cursor(0)[1]
      if M.state.todo_tasks and lnum > 0 and lnum <= #M.state.todo_tasks then
        vim.ui.select({"pending", "in_progress", "done"}, {
          prompt = i18n.get_current_language() == "spanish" and "Cambiar estado a:" or "Change status to:"
        }, function(choice)
          if choice then
            M.change_task_status(lnum, choice, bufnr)
          end
        end)
      end
    end,
    desc = "Change task status",
  })

  -- Añadir mapeo para mostrar ayuda
  api.nvim_buf_set_keymap(bufnr, "n", "?", "", {
    noremap = true,
    callback = function()
      local help

      if i18n.get_current_language() == "spanish" then
        help = {
          "Atajos de teclado para TODOs:",
          "",
          "<CR> - Ver detalles de la tarea",
          "r    - Actualizar lista de tareas",
          "f    - Filtrar por estado",
          "p    - Filtrar por prioridad",
          "s    - Cambiar estado de tarea",
          "P    - Cambiar prioridad de tarea (en vista de detalles)",
          "i    - Implementar tarea seleccionada",
          "?    - Mostrar esta ayuda",
          "q    - Cerrar ventana",
        }
      else
        help = {
          "Keyboard shortcuts for TODOs:",
          "",
          "<CR> - View task details",
          "r    - Refresh task list",
          "f    - Filter by status",
          "p    - Filter by priority",
          "s    - Change task status",
          "P    - Change task priority (in details view)",
          "i    - Implement selected task",
          "?    - Show this help",
          "q    - Close window",
        }
      end

      local popup_buf = api.nvim_create_buf(false, true)
      api.nvim_buf_set_lines(popup_buf, 0, -1, false, help)

      local width = 50
      local height = #help
      local row = math.floor((vim.o.lines - height) / 2)
      local col = math.floor((vim.o.columns - width) / 2)

      local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded"
      }

      local popup_win = api.nvim_open_win(popup_buf, true, opts)
      api.nvim_buf_set_option(popup_buf, "modifiable", false)
      api.nvim_buf_set_keymap(popup_buf, "n", "q", "<cmd>bd!<CR>", {noremap = true, silent = true})
      api.nvim_buf_set_keymap(popup_buf, "n", "<Esc>", "<cmd>bd!<CR>", {noremap = true, silent = true})
    end,
    desc = "Show help",
  })

  -- Añadir mapeo para cerrar la ventana
  api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>bd!<CR>", {noremap = true, silent = true})

  -- Añadir mapeo para implementar la tarea seleccionada
  api.nvim_buf_set_keymap(bufnr, "n", "i", "", {
    noremap = true,
    callback = function()
      local lnum = api.nvim_win_get_cursor(0)[1]
      if M.state.todo_tasks and lnum > 0 and lnum <= #M.state.todo_tasks then
        local task = M.state.todo_tasks[lnum]
        M.state.selected_task = task
        M.state.selected_task_index = lnum
        M.implement_task(task)
      end
    end,
    desc = "Implement selected task",
  })
end

function M.show_selected_task_details()
  local buf = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local title = extract_todo_title(lines)
  -- tasks start at line 3 (after title and blank)
  local tasks = {}
  for i = 3, #lines - 3 do
    local line = lines[i]
    if line and line:match("%S") then
      table.insert(tasks, line)
    end
  end
  local idx = line_nr - 2
  if idx < 1 or idx > #tasks then return end

  -- Reparse original file to get full details
  local todo_path = get_paths().todo_path
  local orig_lines = {}
  if todo_path and vim.fn.filereadable(todo_path) == 1 then
    orig_lines = vim.fn.readfile(todo_path)
  end
  local orig_tasks = parse_todo_markdown(todo_path)
  local task = orig_tasks[idx]
  if task then
    M.show_task_details(task)
  end
end

-- Mostrar una ventana de ayuda para el módulo de TODOs
function M.show_help_window()
  local content = {
    "# Ayuda para el módulo de TODOs",
    "",
    "## Atajos de teclado",
    "",
    "- `<CR>` : Ver detalles de la tarea",
    "- `r`    : Actualizar lista de tareas desde el contexto",
    "- `f`    : Filtrar tareas por estado",
    "- `p`    : Filtrar tareas por prioridad",
    "- `s`    : Cambiar estado de la tarea seleccionada",
    "- `?`    : Mostrar esta ayuda",
    "- `q`    : Cerrar ventana",
    "",
    "## Estados disponibles",
    "",
    "- `pending`     : Tarea pendiente",
    "- `in_progress` : Tarea en progreso",
    "- `done`        : Tarea completada",
    "",
    "## Prioridades",
    "",
    "- `1`: Crítica",
    "- `2`: Alta",
    "- `3`: Media (default)",
    "- `4`: Baja",
    "- `5`: Opcional",
  }

  return M.create_floating_window({
    title = "Ayuda de TODOs",
    content = content,
    width = 60,
    height = #content + 2,
    filetype = "markdown"
  })
end

-- Mostrar estadísticas de tareas
function M.show_todo_stats(tasks)
  local total = #tasks
  local pending = 0
  local in_progress = 0
  local done = 0

  for _, task in ipairs(tasks) do
    local status = (task.status or ""):lower()
    if status:find("done") then
      done = done + 1
    elseif status:find("progress") then
      in_progress = in_progress + 1
    else
      pending = pending + 1
    end
  end

  local progress = total > 0 and math.floor((done / total) * 100) or 0

  local content = {
    "# Estadísticas de TODOs",
    "",
    "- **Total tareas**: " .. total,
    "- **Pendientes**: " .. pending,
    "- **En progreso**: " .. in_progress,
    "- **Completadas**: " .. done,
    "- **Progreso**: " .. progress .. "%",
    "",
    string.rep("█", math.floor(progress / 5)) .. string.rep("░", 20 - math.floor(progress / 5)),
  }

  return M.create_floating_window({
    title = "Estadísticas",
    content = content,
    width = 50,
    height = #content + 2,
    filetype = "markdown"
  })
end

-- Permitir elegir una tarea y ejecutar acción sobre ella
function M.select_task(tasks, title, action_callback)
  if not tasks or #tasks == 0 then
    vim.notify("No hay tareas disponibles", vim.log.levels.WARN)
    return
  end

  -- Crear opciones para selector
  local options = {}
  for i, task in ipairs(tasks) do
    local priority = task.priority or "3"
    local status = task.status or "pending"
    table.insert(options, string.format("[%s][%s] %s", priority, status, task.title or ""))
  end

  vim.ui.select(options, {
    prompt = title,
    format_item = function(item)
      return item
    end
  }, function(choice, idx)
    if choice and idx and action_callback then
      action_callback(tasks[idx], idx)
    end
  end)
end

-- Main: Generate TODO file from context
function M.generate_todo(callback)
  -- Read requirement content
  local paths = get_paths()
  local requirement = file_utils.read_file(paths.requirement) or ""
  local ticket_synthesis = file_utils.read_file(paths.synthesis) or ""
  local project_synthesis = file_utils.read_file(paths.project_context) or ""
  local todo = file_utils.read_file(paths.todo_path) or ""
  local full_context = requirement .. "\n" .. ticket_synthesis .. "\n" .. project_synthesis

  -- Generar prompt para TODOs
  local prompt = require("copilotchatassist.prompts.todo_requests").default(full_context, ticket_synthesis, todo)

  -- Usar log con traducción automática
  log.info({
    english = "Starting to refresh TODOs...",
    spanish = "Comenzando a actualizar TODOs..."
  })

  copilot_api.ask(prompt, {
    headless = true,
    callback = function(response)
      local content = response

      -- Verificar si la respuesta es una tabla con campo content
      if type(response) == "table" and response.content then
        log.debug({
          english = "Response is a table, extracting content field",
          spanish = "La respuesta es una tabla, extrayendo campo content"
        })
        content = response.content
      elseif type(response) ~= "string" then
        log.error({
          english = "Unexpected response format: " .. type(response),
          spanish = "Formato de respuesta inesperado: " .. type(response)
        })
        content = vim.inspect(response)
      end

      -- Guardamos la respuesta raw para debug
      local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
      vim.fn.mkdir(debug_dir, "p")
      local raw_file = debug_dir .. "/todo_raw.txt"
      local raw_debug_file = io.open(raw_file, "w")
      if raw_debug_file then
        raw_debug_file:write(content or "")
        raw_debug_file:close()
      end

      -- Verificar si necesitamos traducir el contenido
      local user_language = options.get().language
      local current_language = nil

      -- Detectar idioma actual del contenido con más patrones
      if content and (content:match("integración") or content:match("validación") or
         content:match("documentación") or content:match("PENDIENTE") or content:match("Total Tareas") or
         content:match("pendientes") or content:match("listas") or content:match("%% avance") or
         content:match("refactor") or content:match("implementar") or content:match("revisar")) then
        current_language = "spanish"
        log.debug({
          english = "Detected Spanish content in the response",
          spanish = "Se detectó contenido en español en la respuesta"
        })
      else
        current_language = "english"
        log.debug({
          english = "Detected English content or no specific pattern matched",
          spanish = "Se detectó contenido en inglés o ningún patrón específico coincidió"
        })
      end

      -- Si el idioma actual no coincide con el configurado, realizar traducción
      if current_language ~= user_language and user_language == "english" and content then
        log.debug({
          english = "Content language doesn't match configured language. Translating from Spanish to English",
          spanish = "El idioma del contenido no coincide con el idioma configurado. Traduciendo de español a inglés"
        })

        -- Realizar traducciones específicas para categorías y estados
        content = content:gsub("integración", "integration")
        content = content:gsub("validación", "validation")
        content = content:gsub("documentación", "documentation")
        content = content:gsub("interfaz", "interface")
        content = content:gsub("testing", "testing")
        content = content:gsub("formato", "format")
        content = content:gsub("core", "core")
        content = content:gsub("TODO", "TODO")
        content = content:gsub("PENDIENTE", "TODO")
        content = content:gsub("EN PROGRESO", "IN PROGRESS")
        content = content:gsub("COMPLETADO", "DONE")
        content = content:gsub("Total Tareas:", "Total Tasks:")
        content = content:gsub("Total pendientes:", "Total pending:")
        content = content:gsub("Total listas:", "Total completed:")
        content = content:gsub("%% avance:", "%% progress:")
      end

      file_utils.write_file(paths.todo_path, content or "")

      -- Command completion - show simple notification at INFO level
      vim.notify("TODOs updated.", vim.log.levels.INFO, { timeout = 2000 })

      -- Si hay callback, ejecutarla
      if callback and type(callback) == "function" then
        callback()
      end
    end
  })
end

-- Implementar una tarea mediante CopilotChat y capturar patches
function M.implement_task(task)
  if not task then
    log.warn({
      english = "No task selected to implement",
      spanish = "No hay tarea seleccionada para implementar"
    })
    return
  end

  -- Usar la API de CopilotChat para solicitar implementación
  log.info({
    english = "Requesting implementation for: " .. task.title,
    spanish = "Solicitando implementación para: " .. task.title
  })

  local patches_module = require("copilotchatassist.patches")
  copilot_api.implement_task(task, function(response, patches_count)
    if patches_count > 0 then
      -- Command completion - show at INFO level with simple message
      vim.notify(string.format("Task implementation generated %d patches.", patches_count), vim.log.levels.INFO, { timeout = 2000 })

      -- Preguntar si desea ver los patches ahora
      vim.defer_fn(function()
        local yes_option = i18n.get_current_language() == "spanish" and "Sí" or "Yes"
        local no_option = "No"
        local prompt = i18n.get_current_language() == "spanish"
          and "¿Deseas ver los patches generados ahora?"
          or "Do you want to see the generated patches now?"

        vim.ui.select({yes_option, no_option}, {
          prompt = prompt
        }, function(choice)
          if choice == yes_option then
            patches_module.show_patch_window()
          end
        end)
      end, 500)
    else
      -- Command completion - show at INFO level with simple message
      vim.notify("Task implementation complete. No patches generated.", vim.log.levels.INFO, { timeout = 2000 })
    end

    -- Si la tarea estaba pendiente, marcarla como en progreso
    if task.status:lower() == "pending" or task.status:lower() == "todo" then
      M.change_task_status(M.state.selected_task_index, "in_progress", M.state.todo_split and M.state.todo_split.buf)
    end
  end)
end

return M