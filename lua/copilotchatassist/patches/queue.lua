-- Módulo para gestión de colas de patches
-- Migrado y adaptado desde CopilotFiles

local M = {}
local log = require("copilotchatassist.utils.log")

-- Constructor para crear una nueva cola de patches
function M.new()
  local queue = {
    items = {},       -- Lista de patches
    hashes = {},      -- Hash de patches para evitar duplicados
    count = 0,        -- Contador de patches
    applied = 0,      -- Contador de patches aplicados
    failed = 0,       -- Contador de patches fallidos
  }

  -- Agregar un patch a la cola
  -- @param patch tabla: El patch a agregar
  -- @param hash string: Hash único del patch (opcional)
  -- @return boolean: true si se agregó, false si ya existía
  function queue:enqueue(patch, hash)
    -- Generar hash si no se proporcionó
    hash = hash or require("copilotchatassist.patches.parser").generate_patch_hash(patch)

    -- Verificar si el patch ya está en la cola
    if self.hashes[hash] then
      log.debug("Patch duplicado no agregado: " .. hash)
      return false
    end

    -- Añadir patch a la cola
    patch.estado = patch.estado or "pendiente"
    patch.hash = hash
    table.insert(self.items, patch)
    self.hashes[hash] = #self.items
    self.count = self.count + 1

    log.debug("Patch agregado a la cola: " .. hash)
    return true
  end

  -- Obtener un patch por su índice
  -- @param index número: Índice del patch (1-based)
  -- @return tabla: El patch o nil si no existe
  function queue:get(index)
    return self.items[index]
  end

  -- Obtener un patch por su hash
  -- @param hash string: Hash del patch
  -- @return tabla, número: El patch y su índice, o nil si no existe
  function queue:get_by_hash(hash)
    local index = self.hashes[hash]
    if index then
      return self.items[index], index
    end
    return nil, nil
  end

  -- Actualizar el estado de un patch
  -- @param index número: Índice del patch (1-based)
  -- @param estado string: Nuevo estado ("pendiente", "aplicado", "fallido")
  -- @return boolean: true si se actualizó, false si no existe
  function queue:update_status(index, estado)
    local patch = self.items[index]
    if not patch then
      log.warn("Intento de actualizar estado de patch inexistente: " .. tostring(index))
      return false
    end

    local old_estado = patch.estado
    patch.estado = estado

    -- Actualizar contadores
    if old_estado == "aplicado" then self.applied = self.applied - 1 end
    if old_estado == "fallido" then self.failed = self.failed - 1 end

    if estado == "aplicado" then self.applied = self.applied + 1 end
    if estado == "fallido" then self.failed = self.failed + 1 end

    log.debug("Estado de patch actualizado: " .. index .. " -> " .. estado)
    return true
  end

  -- Eliminar un patch de la cola
  -- @param index número: Índice del patch (1-based)
  -- @return boolean: true si se eliminó, false si no existe
  function queue:remove(index)
    local patch = self.items[index]
    if not patch then
      log.warn("Intento de eliminar patch inexistente: " .. tostring(index))
      return false
    end

    -- Actualizar contadores
    if patch.estado == "aplicado" then self.applied = self.applied - 1 end
    if patch.estado == "fallido" then self.failed = self.failed - 1 end

    -- Eliminar hash
    self.hashes[patch.hash] = nil

    -- Eliminar patch
    table.remove(self.items, index)
    self.count = self.count - 1

    -- Actualizar índices en el hash
    for i = index, #self.items do
      local p = self.items[i]
      if p and p.hash then
        self.hashes[p.hash] = i
      end
    end

    log.debug("Patch eliminado de la cola: " .. index)
    return true
  end

  -- Limpiar la cola
  function queue:clear()
    self.items = {}
    self.hashes = {}
    self.count = 0
    self.applied = 0
    self.failed = 0
    log.debug("Cola de patches limpiada")
  end

  -- Obtener estadísticas de la cola
  -- @return tabla: Estadísticas de la cola
  function queue:stats()
    return {
      total = self.count,
      pending = self.count - self.applied - self.failed,
      applied = self.applied,
      failed = self.failed,
    }
  end

  return queue
end

return M