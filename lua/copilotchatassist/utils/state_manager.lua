-- Módulo para gestión centralizada de estado en operaciones asíncronas
-- Evita condiciones de carrera y proporciona funciones para rastrear operaciones

local M = {}

-- Almacenamiento de operaciones por tipo
M.operations = {
  pr_generation = nil,     -- Operación actual de generación de PR
  pr_update = nil,         -- Operación actual de actualización de PR
  context_analysis = nil,  -- Operación actual de análisis de contexto
  todo_generation = nil,   -- Operación actual de generación de TODOs
}

-- Log para operaciones de estado
local log = require("copilotchatassist.utils.log")

-- Genera un ID único para una operación
function M.generate_operation_id(operation_type)
  local timestamp = os.time()
  local random_part = math.random(1000, 9999)
  return operation_type .. "_" .. timestamp .. "_" .. random_part
end

-- Inicia una operación con un tipo específico
-- Retorna un objeto de operación con ID y funciones para gestionar su estado
function M.start_operation(operation_type)
  -- Verificar si ya existe una operación de este tipo
  if M.operations[operation_type] then
    log.debug("Cancelando operación existente de tipo " .. operation_type .. ": " .. M.operations[operation_type].id)
    
    -- Cancelar operación existente
    if M.operations[operation_type].cancel then
      M.operations[operation_type].cancel("Reemplazada por nueva operación")
    end
  end
  
  -- Generar ID único para esta operación
  local id = M.generate_operation_id(operation_type)
  
  -- Crear objeto de operación
  local operation = {
    id = id,
    type = operation_type,
    start_time = os.time(),
    status = "running",
    
    -- Método para verificar si esta operación sigue siendo la actual
    is_current = function(self)
      return M.operations[operation_type] and M.operations[operation_type].id == self.id
    end,
    
    -- Método para completar la operación
    complete = function(self)
      if self:is_current() then
        log.debug("Completando operación " .. self.id)
        M.operations[operation_type] = nil
        return true
      end
      return false
    end,
    
    -- Método para cancelar la operación
    cancel = function(self, reason)
      if self:is_current() then
        log.debug("Cancelando operación " .. self.id .. (reason and (": " .. reason) or ""))
        M.operations[operation_type] = nil
        return true
      end
      return false
    end,
    
    -- Método para actualizar el estado de la operación
    update = function(self, new_status, data)
      if self:is_current() then
        self.status = new_status
        if data then
          self.data = data
        end
        return true
      end
      return false
    end
  }
  
  -- Registrar como operación actual
  M.operations[operation_type] = operation
  log.debug("Iniciada operación " .. operation_type .. " con ID " .. id)
  
  return operation
end

-- Verifica si una operación con un ID específico sigue siendo la actual
function M.is_operation_current(operation_type, operation_id)
  return M.operations[operation_type] and M.operations[operation_type].id == operation_id
end

-- Completa una operación por tipo e ID
function M.complete_operation(operation_type, operation_id)
  if M.is_operation_current(operation_type, operation_id) then
    log.debug("Completando operación " .. operation_id)
    M.operations[operation_type] = nil
    return true
  end
  return false
end

-- Cancela una operación por tipo e ID
function M.cancel_operation(operation_type, operation_id, reason)
  if M.is_operation_current(operation_type, operation_id) then
    log.debug("Cancelando operación " .. operation_id .. (reason and (": " .. reason) or ""))
    M.operations[operation_type] = nil
    return true
  end
  return false
end

-- Cancela todas las operaciones de un tipo específico
function M.cancel_operations_by_type(operation_type, reason)
  if M.operations[operation_type] then
    log.debug("Cancelando operación de tipo " .. operation_type .. ": " .. M.operations[operation_type].id .. 
              (reason and (": " .. reason) or ""))
    M.operations[operation_type] = nil
    return true
  end
  return false
end

-- Resetea todas las operaciones
function M.reset_all(reason)
  log.info("Reseteando todas las operaciones" .. (reason and (": " .. reason) or ""))
  for operation_type, operation in pairs(M.operations) do
    if operation then
      log.debug("Cancelando operación " .. operation.id .. " de tipo " .. operation_type)
    end
  end
  M.operations = {}
end

-- Iniciar el monitor de operaciones para detectar bloqueos
function M.start_operation_monitor()
  local monitor_timer = vim.loop.new_timer()
  
  -- Verificar operaciones cada 30 segundos
  monitor_timer:start(30000, 30000, vim.schedule_wrap(function()
    local now = os.time()
    local ops_cleaned = false
    
    -- Revisar cada operación
    for operation_type, operation in pairs(M.operations) do
      if operation then
        local elapsed = now - operation.start_time
        
        -- Si una operación lleva más de 5 minutos, cancelarla
        if elapsed > 300 then
          log.warn("Operación " .. operation.id .. " de tipo " .. operation_type .. 
                   " ha estado ejecutándose por " .. elapsed .. " segundos, cancelando")
          M.operations[operation_type] = nil
          ops_cleaned = true
        end
      end
    end
    
    -- Notificar si se limpiaron operaciones
    if ops_cleaned then
      local notify = require("copilotchatassist.utils.notify")
      notify.warn("Se han cancelado operaciones bloqueadas")
    end
  end))
  
  return monitor_timer
end

-- Inicializar el módulo
function M.setup()
  -- Iniciar monitor de operaciones
  M.monitor = M.start_operation_monitor()
  log.info("Gestor de estado de operaciones inicializado")
 end

return M