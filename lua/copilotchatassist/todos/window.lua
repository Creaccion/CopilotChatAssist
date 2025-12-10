-- Módulo para manejo avanzado de ventanas de TODOs
local M = {}

local api = vim.api
local file_utils = require("copilotchatassist.utils.file")
local options = require("copilotchatassist.options")

-- Almacenar información sobre ventanas flotantes
M.floating_windows = {}

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
  local win_id = #M.floating_windows + 1
  M.floating_windows[win_id] = {
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
      M.floating_windows[win_id] = nil
    end,
    once = true
  })

  return win_id
end

-- Actualizar contenido de ventana flotante
function M.update_window_content(win_id, content)
  local window = M.floating_windows[win_id]
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
  local window = M.floating_windows[win_id]
  if not window or not api.nvim_win_is_valid(window.win) then
    return false
  end

  api.nvim_win_close(window.win, true)
  M.floating_windows[win_id] = nil

  return true
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
    string.rep("ˆ", math.floor(progress / 5)) .. string.rep("‘", 20 - math.floor(progress / 5)),
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

return M