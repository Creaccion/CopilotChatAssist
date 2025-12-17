-- Módulo para mostrar indicadores visuales de progreso (spinner, barras de progreso)
-- para operaciones largas en CopilotChatAssist.

local M = {}
local api = vim.api
local i18n = require("copilotchatassist.i18n")
local log = require("copilotchatassist.utils.log")
local options = require("copilotchatassist.options")

-- Variables globales para almacenar estados de progreso
local active_spinners = {}
local spinner_namespace = nil
local progress_timers = {}
local progress_windows = {}

-- Diferentes estilos de spinner disponibles
local spinner_styles = {
  dots = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
  line = {"|", "/", "-", "\\"},
  braille = {"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"},
  circle = {"◜", "◠", "◝", "◞", "◡", "◟"},
  moon = {"🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"},
  arrow = {"▹▹▹▹▹", "▸▹▹▹▹", "▹▸▹▹▹", "▹▹▸▹▹", "▹▹▹▸▹", "▹▹▹▹▸"},
  bar = {"[     ]", "[=    ]", "[==   ]", "[===  ]", "[==== ]", "[=====]"},
}

-- Estado para barra de progreso
local progress_state = {
  active = false,
  title = "",
  percentage = 0,
  width = 30, -- Ancho por defecto de la barra
}

-- Verifica si se debe usar el spinner o no según la configuración
local function should_use_progress()
  local config = options.get()
  return config.use_progress_indicator ~= false
end

-- Verifica si hay un spinner activo con el ID dado
function M.is_active(id)
  return active_spinners[id] ~= nil
end

-- Inicializar el namespace para los spinners si no existe
local function ensure_namespace()
  if not spinner_namespace then
    spinner_namespace = api.nvim_create_namespace("copilotchatassist_spinner")
  end
end

-- Crear una ventana flotante para mostrar progreso
local function create_progress_window(title, width, height)
  -- Crear buffer
  local buf = api.nvim_create_buf(false, true)

  -- Configurar buffer
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "swapfile", false)
  api.nvim_buf_set_option(buf, "modifiable", true)

  -- Calcular tamaño y posición
  width = width or 50
  height = height or 3

  -- Posicionar en la parte inferior centrada
  local win = api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = vim.o.lines - height - 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    zindex = 100, -- Mayor zindex para estar siempre encima
  })

  -- Configurar ventana
  api.nvim_win_set_option(win, "winhl", "Normal:NormalFloat")

  return { win = win, buf = buf }
end

-- Actualizar contenido de la ventana de progreso
local function update_progress_window(progress_window, content)
  if not progress_window or not progress_window.buf or not api.nvim_buf_is_valid(progress_window.buf) then
    return false
  end

  -- Actualizar contenido
  api.nvim_buf_set_option(progress_window.buf, "modifiable", true)
  api.nvim_buf_set_lines(progress_window.buf, 0, -1, false, content)
  api.nvim_buf_set_option(progress_window.buf, "modifiable", false)

  return true
end

-- Cerrar ventana de progreso
local function close_progress_window(progress_window)
  if not progress_window then return end

  -- Cerrar ventana si es válida
  if progress_window.win and api.nvim_win_is_valid(progress_window.win) then
    api.nvim_win_close(progress_window.win, true)
  end

  -- Eliminar buffer si es válido
  if progress_window.buf and api.nvim_buf_is_valid(progress_window.buf) then
    api.nvim_buf_delete(progress_window.buf, { force = true })
  end
end

-- Inicia un nuevo spinner con un ID único
-- @param id string: Identificador único para el spinner
-- @param message string: Mensaje a mostrar junto al spinner
-- @param opts table: Opciones adicionales (style, position, etc.)
function M.start_spinner(id, message, opts)
  if not should_use_progress() then
    -- Si los indicadores de progreso están desactivados, solo registrar en log
    log.debug("Iniciando operación: " .. message)
    return
  end

  ensure_namespace()
  opts = opts or {}

  -- Detener spinner existente con el mismo ID si existe
  if active_spinners[id] then
    M.stop_spinner(id)
  end

  -- Crear estado para el nuevo spinner
  local style = opts.style or "dots"
  local frames = spinner_styles[style] or spinner_styles.dots
  local position = opts.position or "statusline"
  local speed = opts.speed or 100 -- ms por frame

  -- Guardar el estado del spinner
  active_spinners[id] = {
    frames = frames,
    current_frame = 1,
    message = message,
    position = position,
    start_time = os.time(),
    color = opts.color or "Special",
    is_modal = opts.modal == true,
    timer = nil
  }

  -- Si es modal, crear una ventana flotante
  if active_spinners[id].is_modal then
    progress_windows[id] = create_progress_window(message, opts.width, opts.height)
    update_progress_window(progress_windows[id], {frames[1] .. " " .. message})
  end

  -- Iniciar el timer para actualizar el spinner
  local timer = vim.loop.new_timer()
  active_spinners[id].timer = timer

  timer:start(0, speed, vim.schedule_wrap(function()
    if not active_spinners[id] then
      -- El spinner fue detenido
      return
    end

    local spinner = active_spinners[id]
    spinner.current_frame = (spinner.current_frame % #spinner.frames) + 1
    local frame = spinner.frames[spinner.current_frame]
    local elapsed = os.time() - spinner.start_time
    local display = frame .. " " .. spinner.message .. " (" .. elapsed .. "s)"

    if spinner.position == "statusline" then
      -- Actualizar la barra de estado
      vim.cmd("redrawstatus")

      -- Opcionalmente, mostrar en echo area
      vim.cmd(string.format([[echohl %s | echo "%s" | echohl NONE]], spinner.color, display))
    elseif spinner.position == "window" and progress_windows[id] then
      -- Actualizar ventana flotante
      update_progress_window(progress_windows[id], {display})
    end
  end))

  progress_timers[id] = timer

  return active_spinners[id]
end

-- Detiene un spinner por su ID
-- @param id string: Identificador único del spinner
-- @param success boolean: Si la operación fue exitosa o no
function M.stop_spinner(id, success)
  if not active_spinners[id] then
    return
  end

  -- Detener y cerrar el timer
  if active_spinners[id].timer then
    active_spinners[id].timer:stop()
    active_spinners[id].timer:close()
  end

  -- Calcular tiempo total
  local elapsed = os.time() - active_spinners[id].start_time

  -- Si hay ventana flotante, cerrarla
  if progress_windows[id] then
    -- Actualizar mensaje final antes de cerrar
    local final_msg
    if success ~= nil then
      final_msg = success and "✓ " or "✗ "
    else
      final_msg = "• "
    end

    -- Si es exitoso, quitar el contador de tiempo y mostrar solo el check verde
    if success then
      final_msg = final_msg .. active_spinners[id].message
    else
      -- En caso de error o estado neutro, mantener el contador de tiempo
      final_msg = final_msg .. active_spinners[id].message .. " (" .. elapsed .. "s)"
    end
    update_progress_window(progress_windows[id], {final_msg})

    -- Cerrar después de un retraso
    vim.defer_fn(function()
      close_progress_window(progress_windows[id])
      progress_windows[id] = nil
    end, 1000) -- Mostrar mensaje final por 1 segundo
  end

  -- Mostrar mensaje final en statusline si corresponde
  if active_spinners[id].position == "statusline" then
    -- Construir mensaje final sin contador de tiempo para éxito
    local final_display
    if success ~= nil then
      final_display = success and ("✓ " .. active_spinners[id].message) or
                           ("✗ " .. active_spinners[id].message .. " (" .. elapsed .. "s)")
    else
      final_display = "• " .. active_spinners[id].message .. " (" .. elapsed .. "s)"
    end

    -- Mostrar en echo area
    local color = success and "String" or (success == false and "WarningMsg" or active_spinners[id].color)
    vim.cmd(string.format([[echohl %s | echo "%s" | echohl NONE]], color, final_display))
    vim.cmd("redrawstatus")

    -- Programar limpieza del mensaje después de un tiempo
    vim.defer_fn(function() vim.cmd("echo ''") end, 2000)
  else
    -- Limpiar echo area inmediatamente para otros casos
    vim.cmd("echo ''")
  end

  -- Eliminar el spinner y timer
  active_spinners[id] = nil
  progress_timers[id] = nil
end

-- Actualizar mensaje del spinner
-- @param id string: Identificador único del spinner
-- @param message string: Nuevo mensaje para el spinner
function M.update_spinner(id, message)
  if not active_spinners[id] then
    return
  end

  active_spinners[id].message = message
end

-- Mostrar una barra de progreso
-- @param title string: Título para la barra de progreso
-- @param percentage number: Porcentaje completado (0-100)
-- @param opts table: Opciones adicionales
function M.show_progress_bar(title, percentage, opts)
  if not should_use_progress() then
    return
  end

  opts = opts or {}

  -- Asegurarse de que el porcentaje esté entre 0 y 100
  percentage = math.max(0, math.min(100, percentage))

  -- Actualizar estado
  progress_state.active = true
  progress_state.title = title
  progress_state.percentage = percentage
  progress_state.width = opts.width or progress_state.width

  -- Crear o actualizar ventana si es necesario
  if not progress_state.window or not api.nvim_win_is_valid(progress_state.window.win) then
    progress_state.window = create_progress_window(
      title,
      progress_state.width + 10,
      3
    )
  end

  -- Generar barra de progreso
  local bar_width = progress_state.width
  local completed_width = math.floor(percentage * bar_width / 100)
  local remaining_width = bar_width - completed_width

  local progress_bar = string.format(
    "[%s%s] %d%%",
    string.rep("=", completed_width),
    string.rep(" ", remaining_width),
    percentage
  )

  -- Actualizar ventana
  update_progress_window(progress_state.window, {progress_bar})
end

-- Cerrar barra de progreso
function M.close_progress_bar()
  if not progress_state.active then
    return
  end

  -- Mostrar mensaje de completado
  update_progress_window(progress_state.window, {"Completado"})

  -- Cerrar la ventana después de un breve retraso
  vim.defer_fn(function()
    if progress_state.window then
      close_progress_window(progress_state.window)
      progress_state.window = nil
    end
    progress_state.active = false
  end, 1000)
end

-- Obtener el contenido del spinner actual para mostrar en statusline
-- Para usar en conjunto con una función de statusline personalizada
function M.get_statusline_spinner()
  -- Verificar si hay algún spinner activo
  local active_spinner = nil
  for id, spinner in pairs(active_spinners) do
    if spinner.position == "statusline" then
      active_spinner = spinner
      break
    end
  end

  if not active_spinner then
    return ""
  end

  -- Obtener el frame actual
  local frame = active_spinner.frames[active_spinner.current_frame]
  local elapsed = os.time() - active_spinner.start_time

  return string.format("%s %s (%ds)", frame, active_spinner.message, elapsed)
end

-- Limpia todos los spinners activos
function M.clear_all_spinners()
  for id, _ in pairs(active_spinners) do
    M.stop_spinner(id)
  end
end

-- Inicializar el módulo (se llama en el init del plugin)
function M.setup()
  -- Agregar un grupo de autocomandos para limpiar spinners al salir
  vim.api.nvim_create_augroup("CopilotChatAssistSpinner", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = "CopilotChatAssistSpinner",
    callback = function()
      M.clear_all_spinners()
    end,
  })
end

return M