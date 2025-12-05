-- Módulo para la visualización y gestión de patches en ventanas
-- Migrado y adaptado desde CopilotFiles

local M = {}
local log = require("copilotchatassist.utils.log")

-- Estado del módulo
M.state = {
  patches = {},         -- Lista de patches formateados para visualización
  window = nil,         -- Información de la ventana actual
  selected_patch = nil, -- Índice del patch seleccionado
}

-- Traduce estado de patch a icono para visualización
local function get_state_icon(state)
  if state == "aplicado" then
    return "✓"
  elseif state == "fallido" then
    return "✗"
  else
    return "□"
  end
end

-- Añadir un patch formateado para visualización
-- @param patch table: Patch formateado para visualización
function M.add_patch(patch)
  table.insert(M.state.patches, patch)
  log.debug("Patch añadido a visualización: " .. (patch.id or "?"))
end

-- Sincronizar patches con la cola
-- @param patch_queue table: Cola de patches
function M.sync_patches(patch_queue)
  log.debug("Sincronizando patches para visualización")
  M.state.patches = {}

  if not patch_queue or not patch_queue.items then
    log.warn("Cola de patches inválida para sincronización")
    return
  end

  for idx, patch in ipairs(patch_queue.items) do
    M.add_patch({
      id = idx,
      file = patch.archivo or "?",
      range = patch.start_line and patch.end_line and
              (tostring(patch.start_line) .. "-" .. tostring(patch.end_line)) or "?",
      state = patch.estado or "pendiente",
      detail = patch.modo or "",
      content = patch.block or "",
    })
  end

  log.debug("Sincronizados " .. #M.state.patches .. " patches")
end

-- Generar líneas para la visualización de patches
-- @return table: Líneas formateadas para mostrar
local function generate_patch_lines()
  local lines = {
    "Patches pendientes de aplicación:",
    "--------------------------------",
    ""
  }

  for i, patch in ipairs(M.state.patches) do
    local icon = get_state_icon(patch.state)
    local line = string.format("%d. %s [%s] %s (%s) %s",
      i,
      icon,
      patch.detail or "?",
      patch.file or "?",
      patch.range or "?",
      patch.state or "pendiente"
    )
    table.insert(lines, line)
  end

  if #M.state.patches == 0 then
    table.insert(lines, "No hay patches pendientes")
  end

  return lines
end

-- Configurar keymaps para la ventana de patches
-- @param bufnr number: Número de buffer
local function setup_keymaps(bufnr)
  -- Opción para permitir modificar el buffer
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

  -- Definir mappings locales
  local function set_keymap(mode, key, action)
    vim.api.nvim_buf_set_keymap(bufnr, mode, key, action, { noremap = true, silent = true })
  end

  -- Cerrar ventana
  set_keymap("n", "q", ":lua require'copilotchatassist.patches.window'.close_window()<CR>")

  -- Ver detalles del patch
  set_keymap("n", "<CR>", ":lua require'copilotchatassist.patches.window'.show_patch_details()<CR>")

  -- Aplicar patch
  set_keymap("n", "a", ":lua require'copilotchatassist.patches.window'.apply_selected_patch()<CR>")

  -- Eliminar patch
  set_keymap("n", "d", ":lua require'copilotchatassist.patches.window'.remove_selected_patch()<CR>")

  -- Refrescar vista
  set_keymap("n", "r", ":lua require'copilotchatassist.patches.window'.refresh_window()<CR>")

  -- Ayuda
  set_keymap("n", "?", ":lua require'copilotchatassist.patches.window'.show_help()<CR>")
end

-- Mostrar la ventana de patches en estilo split horizontal inferior
-- @param patch_queue table: Cola de patches (opcional)
function M.show_patch_window(patch_queue)
  -- Sincronizar patches si se proporciona cola
  if patch_queue then
    M.sync_patches(patch_queue)
  end

  log.debug("Mostrando ventana de patches")

  -- Generar líneas para mostrar
  local lines = generate_patch_lines()

  -- Crear buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Configuración de buffer
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "copilotpatches")

  -- Determinar altura de la ventana split (25% o mínimo 10 líneas)
  local height = math.max(10, math.floor(vim.o.lines * 0.25))

  -- Crear ventana split
  vim.cmd("botright " .. height .. "split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Guardar referencia a ventana y buffer
  M.state.window = {
    win = win,
    buf = buf
  }

  -- Configurar keymaps
  setup_keymaps(buf)

  log.debug("Ventana de patches abierta")
  return buf
end

-- Mostrar cola de patches (vista simplificada)
-- @param patch_queue table: Cola de patches
function M.show_patch_queue(patch_queue)
  if not patch_queue or not patch_queue.items then
    log.warn("Cola de patches inválida para visualización")
    vim.notify("No hay patches disponibles para mostrar", vim.log.levels.INFO)
    return
  end

  -- Crear mensaje de resumen
  local stats = patch_queue:stats()
  local message = string.format("Patches: %d total, %d pendientes, %d aplicados, %d fallidos",
    stats.total, stats.pending, stats.applied, stats.failed)

  vim.notify(message, vim.log.levels.INFO)

  -- Si no hay patches, no mostrar más
  if stats.total == 0 then
    return
  end

  -- Mostrar ventana completa
  M.show_patch_window(patch_queue)
end

-- Cerrar ventana de patches
function M.close_window()
  if M.state.window and M.state.window.win and vim.api.nvim_win_is_valid(M.state.window.win) then
    vim.api.nvim_win_close(M.state.window.win, true)
    M.state.window = nil
    log.debug("Ventana de patches cerrada")
  end
end

-- Refrescar contenido de la ventana de patches
function M.refresh_window()
  if not M.state.window or not vim.api.nvim_win_is_valid(M.state.window.win) then
    log.warn("Intento de refrescar ventana de patches inválida")
    return
  end

  local bufnr = M.state.window.buf
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn("Buffer de ventana de patches inválido")
    return
  }

  -- Habilitar modificación del buffer
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

  -- Actualizar contenido
  local lines = generate_patch_lines()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Deshabilitar modificación
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

  log.debug("Ventana de patches refrescada")
}

-- Mostrar detalles del patch seleccionado
function M.show_patch_details()
  -- Obtener línea actual
  local line = vim.fn.line(".")

  -- Los primeros 3 líneas son el encabezado
  if line <= 3 then
    vim.notify("No hay un patch seleccionado", vim.log.levels.INFO)
    return
  }

  -- Calcular índice del patch (línea - 3)
  local patch_index = line - 3
  if patch_index > #M.state.patches then
    vim.notify("Índice de patch inválido", vim.log.levels.WARN)
    return
  }

  M.state.selected_patch = patch_index
  local patch = M.state.patches[patch_index]
  if not patch then
    vim.notify("Patch no encontrado", vim.log.levels.WARN)
    return
  }

  -- Crear líneas para mostrar
  local detail_lines = {
    string.format("Patch #%d", patch.id),
    string.format("Archivo: %s", patch.file or "?"),
    string.format("Rango: %s", patch.range or "?"),
    string.format("Modo: %s", patch.detail or "?"),
    string.format("Estado: %s", patch.state or "pendiente"),
    "",
    "Contenido:",
    "---------"
  }

  -- Añadir contenido del patch
  for line in (patch.content or ""):gmatch("[^\r\n]+") do
    table.insert(detail_lines, line)
  end

  -- Crear buffer para detalles
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, detail_lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  -- Calcular dimensiones
  local width = math.max(40, math.min(80, vim.o.columns - 10))
  local height = math.max(10, math.min(30, vim.o.lines - 6))

  -- Mostrar ventana flotante
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
  })

  -- Configurar keymap para cerrar
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })

  log.debug("Mostrando detalles de patch #" .. patch_index)
  return buf
}

-- Aplicar el patch seleccionado
function M.apply_selected_patch()
  if not M.state.selected_patch or not M.state.patches[M.state.selected_patch] then
    vim.notify("No hay un patch seleccionado para aplicar", vim.log.levels.INFO)
    return
  end

  local patch_index = M.state.selected_patch
  local visual_patch = M.state.patches[patch_index]

  -- Obtener el patch real desde la cola
  local patches = require("copilotchatassist.patches")
  local patch_queue = patches.get_patch_queue()

  if not patch_queue or not patch_queue.items or not patch_queue.items[visual_patch.id] then
    vim.notify("No se puede encontrar el patch en la cola", vim.log.levels.WARN)
    return
  }

  local patch = patch_queue.items[visual_patch.id]

  -- Aplicar el patch
  local file_manager = require("copilotchatassist.patches.file_manager")
  file_manager.apply_patch(patch, function()
    -- Actualizar estado en la cola
    patch_queue:update_status(visual_patch.id, "aplicado")

    -- Actualizar estado visual
    M.state.patches[patch_index].state = "aplicado"

    -- Refrescar ventana
    M.refresh_window()

    vim.notify("Patch aplicado correctamente", vim.log.levels.INFO)
  })
}

-- Eliminar el patch seleccionado
function M.remove_selected_patch()
  if not M.state.selected_patch or not M.state.patches[M.state.selected_patch] then
    vim.notify("No hay un patch seleccionado para eliminar", vim.log.levels.INFO)
    return
  }

  local patch_index = M.state.selected_patch
  local visual_patch = M.state.patches[patch_index]

  -- Obtener el patch real desde la cola
  local patches = require("copilotchatassist.patches")
  local patch_queue = patches.get_patch_queue()

  if not patch_queue or not patch_queue.items or not patch_queue.items[visual_patch.id] then
    vim.notify("No se puede encontrar el patch en la cola", vim.log.levels.WARN)
    return
  }

  -- Confirmar eliminación
  local confirm = vim.fn.confirm("¿Eliminar patch seleccionado?", "&Sí\n&No", 1)
  if confirm ~= 1 then
    return
  end

  -- Eliminar de la cola
  patch_queue:remove(visual_patch.id)

  -- Eliminar visualización
  table.remove(M.state.patches, patch_index)

  -- Refrescar ventana
  M.refresh_window()

  vim.notify("Patch eliminado correctamente", vim.log.levels.INFO)
}

-- Mostrar ayuda
function M.show_help()
  local help_lines = {
    "Ayuda: Ventana de Patches",
    "------------------------",
    "",
    "q       - Cerrar ventana",
    "<CR>    - Ver detalles del patch",
    "a       - Aplicar patch seleccionado",
    "d       - Eliminar patch seleccionado",
    "r       - Refrescar vista",
    "?       - Mostrar esta ayuda",
  }

  -- Crear buffer para ayuda
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  -- Calcular dimensiones
  local width = 40
  local height = #help_lines

  -- Mostrar ventana flotante
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
  })

  -- Configurar keymap para cerrar
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })
}

return M