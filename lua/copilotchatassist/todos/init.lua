local M = {}

-- Módulo para manejar la visualización y gestión de TODOs

local uv = vim.loop
local file_utils = require("copilotchatassist.utils.file")
local context = require("copilotchatassist.context")
local options = require("copilotchatassist.options")
local utils = require("copilotchatassist.utils")
local log = require("copilotchatassist.utils.log")
local copilot_api = require("copilotchatassist.copilotchat_api")

-- Almacena el estado de la visualización de TODOs
M.state = {
  paths = nil,       -- Rutas a archivos de contexto
  todo_split = nil,  -- Información sobre la ventana split de TODOs (win, buf)
  todo_tasks = {},   -- Tareas actuales
  selected_task = nil, -- Tarea actualmente seleccionada
  selected_task_index = nil, -- Índice de la tarea seleccionada
}

-- Obtener rutas actualizadas desde el contexto
local function get_paths()
  if not M.state.paths then
    M.state.paths = context.get_context_paths()
  end
  return M.state.paths
end

local api = vim.api

-- Estandarización de iconos de estado
local status_icons = {
  -- Versiones en mayúsculas
  ["DONE"] = "✅",
  ["TODO"] = "⬜",
  ["PENDING"] = "⬜",
  ["IN_PROGRESS"] = "🔄",
  ["IN PROGRESS"] = "🔄",

  -- Versiones con iconos
  ["✅ DONE"] = "✅",
  ["⬜ PENDING"] = "⬜",
  ["⬜ TODO"] = "⬜",
  ["✅"] = "✅",
  ["⬜"] = "⬜",

  -- Versiones en minúsculas
  ["done"] = "✅",
  ["todo"] = "⬜",
  ["pending"] = "⬜",
  ["in_progress"] = "🔄",
  ["in progress"] = "🔄",
}

-- Parsea el archivo markdown de TODOs y extrae las tareas
local function parse_todo_markdown(path)
  local tasks = {}
  local lines = {}
  local f = io.open(path, "r")
  if not f then return tasks end
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  -- Find table header
  local header_idx = nil
  for i, line in ipairs(lines) do
    if line:match("|") and line:lower():find("status") then
      header_idx = i
      break
    end
  end
  if not header_idx then return tasks end
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
    end
  end
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

local function show_task_details(task)
  local lines = {
    "Task Details",
    "",
    "Number:      " .. (task.number or ""),
    "Status:      " .. (task.status or ""),
    "Priority:    " .. (task.priority or ""),
    "Category:    " .. (task.category or ""),
    "Title:       " .. (task.title or ""),
    "",
    "Description:",
    (task.description or ""),
  }
  local width = 60
  local height = #lines + 2
  local popup_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
  }
  local popup_win = api.nvim_open_win(popup_buf, true, opts)
  api.nvim_buf_set_option(popup_buf, "modifiable", false)
  api.nvim_buf_set_option(popup_buf, "buftype", "nofile")
  api.nvim_buf_set_keymap(popup_buf, "n", "<Esc>", "<cmd>bd!<CR>", { noremap = true, silent = true })
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
  vim.notify("[CopilotChatAssist][DEBUG] reload_todo_split called", vim.log.levels.DEBUG)

  -- Si se proporciona el estado de la ventana split, usar su buffer
  if M.state.todo_split and not buf then
    if not vim.api.nvim_win_is_valid(M.state.todo_split.win) then
      vim.notify("[CopilotChatAssist][DEBUG] todo_split window is invalid", vim.log.levels.DEBUG)
      return
    end
    buf = M.state.todo_split.buf
  else
    -- Usar el buffer actual si no se proporciona uno
    buf = buf or vim.api.nvim_get_current_buf()
  end

  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    vim.notify("[CopilotChatAssist][DEBUG] Buffer is nil or invalid", vim.log.levels.DEBUG)
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
    vim.notify("[CopilotChatAssist][DEBUG] No tasks found", vim.log.levels.DEBUG)
    table.insert(lines, "No hay tareas disponibles. Usa 'r' para actualizar.")
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
      local hl_group = require("copilotchatassist.options").todo_highlights[priority] or ""
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

  vim.notify(string.format(
    "[CopilotChatAssist][DEBUG] Rendered %d tasks, %d highlights",
    #lines, #highlights
  ), vim.log.levels.DEBUG)
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

  M.display_filtered_tasks(filtered_tasks, buf, "Filtrado por estado: " .. status)
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

  M.display_filtered_tasks(filtered_tasks, buf, "Filtrado por prioridad: " .. priority)
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
    table.insert(lines, "No se encontraron tareas con este filtro.")
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
      local hl_group = require("copilotchatassist.options").todo_highlights[priority] or ""
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
  vim.notify("Use 'r' para volver a la vista completa", vim.log.levels.INFO)
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
      vim.notify("No se pudo encontrar la tarea o formato incorrecto", vim.log.levels.ERROR)
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
      vim.notify("No se pudo encontrar la posición de la tarea en el archivo", vim.log.levels.ERROR)
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

      vim.notify("Estado de tarea actualizado a: " .. new_status, vim.log.levels.INFO)

      -- Recargar la visualización
      reload_todo_split(buf)
    else
      vim.notify("Formato de línea incorrecto: " .. line, vim.log.levels.ERROR)
    end
  else
    vim.notify("Índice de tarea fuera de rango", vim.log.levels.ERROR)
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
        show_task_details(task)
      end
    end,
    desc = "Show task details",
  })

  api.nvim_buf_set_keymap(bufnr, "n", "r", "", {
    noremap = true,
    callback = function()
      vim.notify("Refreshing TODO " .. todo_path, vim.log.levels.INFO)
      M.generate_todo(function()
        reload_todo_split(bufnr)
      end)
    end,
    desc = "Refresh TODO list",
  })

  -- Añadir mapeo para filtrar por estado
  api.nvim_buf_set_keymap(bufnr, "n", "f", "", {
    noremap = true,
    callback = function()
      vim.ui.select({"all", "pending", "in_progress", "done"}, {
        prompt = "Filtrar por estado:"
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
        prompt = "Filtrar por prioridad:"
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
          prompt = "Cambiar estado a:"
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
      local help = {
        "Atajos de teclado para TODOs:",
        "",
        "<CR> - Ver detalles de la tarea",
        "r    - Actualizar lista de tareas",
        "f    - Filtrar por estado",
        "p    - Filtrar por prioridad",
        "s    - Cambiar estado de tarea",
        "i    - Implementar tarea seleccionada",
        "?    - Mostrar esta ayuda",
        "q    - Cerrar ventana",
      }

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
    show_task_details(task)
  end
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

  local prompt = require("copilotchatassist.prompts.todo_requests").default(full_context, ticket_synthesis, todo)
  vim.notify("Starting to refresh TODO... ", vim.log.levels.INFO)
  copilot_api.ask(prompt, {
    headless = true,
    callback = function(response)
      file_utils.write_file(paths.todo_path, response or "")
      vim.notify("Project Requirement TODO saved: " .. paths.todo_path, vim.log.levels.INFO)

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
    vim.notify("No hay tarea seleccionada para implementar", vim.log.levels.WARN)
    return
  end

  -- Usar la API de CopilotChat para solicitar implementación
  vim.notify("Solicitando implementación para: " .. task.title, vim.log.levels.INFO)

  local patches_module = require("copilotchatassist.patches")
  copilot_api.implement_task(task, function(response, patches_count)
    if patches_count > 0 then
      vim.notify(string.format("Se generaron %d patches. Usa :CopilotPatchesWindow para revisarlos.", patches_count), vim.log.levels.INFO)

      -- Preguntar si desea ver los patches ahora
      vim.defer_fn(function()
        vim.ui.select({"Sí", "No"}, {
          prompt = "¿Deseas ver los patches generados ahora?"
        }, function(choice)
          if choice == "Sí" then
            patches_module.show_patch_window()
          end
        end)
      end, 500)
    else
      vim.notify("No se generaron patches de código para esta tarea", vim.log.levels.INFO)
    end

    -- Si la tarea estaba pendiente, marcarla como en progreso
    if task.status:lower() == "pending" or task.status:lower() == "todo" then
      M.change_task_status(M.state.selected_task_index, "in_progress", M.state.todo_split and M.state.todo_split.buf)
    end
  end)
end

return M