-- Módulo principal para la gestión de patches de código desde CopilotChat
-- Migrado desde CopilotFiles

local M = {}
local log = require("copilotchatassist.utils.log")
local parser = require("copilotchatassist.patches.parser")
local queue = require("copilotchatassist.patches.queue")
local file_manager = require("copilotchatassist.patches.file_manager")
local window = require("copilotchatassist.patches.window")

-- Estado del módulo
M.state = {
  patch_queue = nil, -- Cola centralizada de patches
  debug_enabled = false, -- Estado de depuración
}

-- Inicialización del módulo
function M.setup(opts)
  opts = opts or {}

  -- Crear la cola de patches si no existe
  if not M.state.patch_queue then
    M.state.patch_queue = queue.new()
    log.debug("Cola de patches inicializada")
  end

  -- Configurar depuración si está habilitada
  if opts.debug then
    M.set_debug(opts.debug)
  end

  log.debug("Módulo de patches inicializado")
end

-- Activar/desactivar depuración
function M.set_debug(enabled)
  M.state.debug_enabled = enabled
  if enabled then
    log.debug("Depuración de patches activada")
  else
    log.debug("Depuración de patches desactivada")
  end
end

-- Procesa el buffer actual para extraer patches
function M.process_current_buffer()
  local buffer_id = vim.fn.bufnr("%")
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Asegurar que la cola esté inicializada
  if not M.state.patch_queue then
    M.state.patch_queue = queue.new()
  end

  local patches = parser.parse_patches(content)

  local count = 0
  for _, patch in ipairs(patches) do
    local hash = parser.generate_patch_hash(patch)
    if M.state.patch_queue:enqueue(patch, hash) then
      count = count + 1
      log.debug("Patch añadido a la cola: " .. hash)
    else
      log.debug("Patch duplicado ignorado: " .. hash)
    end
  end

  if count > 0 then
    log.info("Se encontraron " .. count .. " nuevos patches")
  else
    log.info("No se encontraron nuevos patches")
  end

  return count
end

-- Obtener la cola de patches
function M.get_patch_queue()
  -- Asegurar que la cola esté inicializada
  if not M.state.patch_queue then
    M.state.patch_queue = queue.new()
  end

  return M.state.patch_queue
end

-- Limpiar la cola de patches
function M.clear_patch_queue()
  log.debug("Limpiando cola de patches")

  -- Asegurar que la cola esté inicializada
  if not M.state.patch_queue then
    M.state.patch_queue = queue.new()
  else
    M.state.patch_queue:clear()
  end

  log.info("Cola de patches limpiada")
end

-- Aplicar todos los patches en la cola
function M.apply_patch_queue()
  log.debug("Aplicando cola de patches")

  -- Asegurar que la cola esté inicializada
  if not M.state.patch_queue then
    log.warn("No hay cola de patches inicializada")
    return
  end

  file_manager.apply_patch_queue(M.state.patch_queue)
end

-- Sincronizar estado con la ventana de patches
function M.sync_patch_window()
  -- Asegurar que la cola esté inicializada
  if not M.state.patch_queue then
    M.state.patch_queue = queue.new()
  end

  window.sync_patches(M.state.patch_queue)
end

-- Mostrar la ventana de patches
function M.show_patch_window()
  -- Asegurar que la cola esté inicializada
  if not M.state.patch_queue then
    M.state.patch_queue = queue.new()
  end

  M.process_current_buffer()
  M.sync_patch_window()
  window.show_patch_window(M.state.patch_queue)
end

-- Mostrar la cola de patches (vista simplificada)
function M.show_patch_queue()
  -- Asegurar que la cola esté inicializada
  if not M.state.patch_queue then
    M.state.patch_queue = queue.new()
  end

  window.show_patch_queue(M.state.patch_queue)
end

-- Procesar respuesta de CopilotChat (para integración)
function M.process_copilot_response(response)
  if not response or type(response) ~= "string" then
    log.debug("Respuesta de CopilotChat inválida")
    return 0
  end

  -- Asegurar que la cola esté inicializada
  if not M.state.patch_queue then
    M.state.patch_queue = queue.new()
  end

  local patches = parser.parse_patches(response)
  local count = 0

  for _, patch in ipairs(patches) do
    local hash = parser.generate_patch_hash(patch)
    if M.state.patch_queue:enqueue(patch, hash) then
      count = count + 1
    end
  end

  if count > 0 then
    log.info("Se encontraron " .. count .. " nuevos patches en la respuesta de CopilotChat")
  end

  return count
end

return M