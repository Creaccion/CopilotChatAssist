-- Módulo para detectar problemas de documentación en código
-- Identifica funciones/clases sin documentación o con documentación desactualizada

local M = {}
local log = require("copilotchatassist.utils.log")
local utils = require("copilotchatassist.documentation.utils")

-- Tipos de problemas de documentación
local ISSUE_TYPES = {
  MISSING = "missing",      -- Sin documentación
  OUTDATED = "outdated",    -- Documentación que no refleja la implementación actual
  INCOMPLETE = "incomplete" -- Documentación parcial (falta parámetros, retorno, etc.)
}

-- Escanea un buffer completo en busca de problemas de documentación
-- @param buffer número: ID del buffer a escanear
-- @param opts tabla: Opciones adicionales para el escaneo (opcional)
-- @return tabla: Lista de elementos con problemas de documentación
function M.scan_buffer(buffer, opts)
  opts = opts or {}
  local filetype = vim.bo[buffer].filetype
  local handler = M._get_language_handler(filetype)

  if not handler then
    log.warn("No hay manejador para el lenguaje: " .. filetype)
    return {}
  end

  log.debug("Escaneando buffer " .. buffer .. " con tipo " .. filetype)

  local items = {}

  -- Caso especial para Java: buscar records primero si se solicita
  if filetype == "java" and (opts.detect_records or opts.include_records) then
    log.debug("Buscando records de Java en buffer " .. buffer)
    local records = handler.detect_java_records(buffer)

    if records and #records > 0 then
      log.debug("Se encontraron " .. #records .. " records de Java")
      for _, record in ipairs(records) do
        table.insert(items, record)
      end
    end
  end

  -- Caso especial para archivos Elixir: configuración y manejo especial para módulos
  if (filetype == "elixir" or filetype == "ex" or filetype == "exs") and
     handler.setup_for_elixir and opts.handle_modules ~= false then
    log.debug("Configurando manejo especial para módulos Elixir")
    handler.setup_for_elixir(buffer)
  end

  -- Escaneo estándar del buffer
  local standard_items = handler.scan_buffer(buffer)

  -- Combinar resultados (evitar duplicados por nombre)
  local seen_names = {}
  for _, item in ipairs(items) do
    seen_names[item.name] = true
  end

  for _, item in ipairs(standard_items) do
    if not seen_names[item.name] then
      table.insert(items, item)
      seen_names[item.name] = true
    end
  end

  log.debug("Se encontraron " .. #items .. " elementos con problemas de documentación")
  return items
end

-- Detecta problemas de documentación en una posición específica
-- @param buffer número: ID del buffer
-- @param row número: Número de fila (1-indexed)
-- @return tabla|nil: Información del elemento encontrado o nil si no se encuentra ninguno
function M.detect_at_position(buffer, row)
  local filetype = vim.bo[buffer].filetype
  local handler = M._get_language_handler(filetype)

  if not handler then
    log.warn("No hay manejador para el lenguaje: " .. filetype)
    return nil
  end

  return handler.detect_at_position(buffer, row)
end

-- Obtiene estadísticas de documentación para un buffer
-- @param buffer número: ID del buffer
-- @return tabla: Estadísticas de documentación
function M.get_doc_stats(buffer)
  local filetype = vim.bo[buffer].filetype
  local handler = M._get_language_handler(filetype)

  if not handler then
    log.warn("No hay manejador para el lenguaje: " .. filetype)
    return {
      total_items = 0,
      documented = 0,
      missing = 0,
      outdated = 0,
      incomplete = 0,
      coverage = 0
    }
  end

  return handler.get_doc_stats(buffer)
end

-- Cache de manejadores de lenguaje para evitar cargarlos repetidamente
M.handlers = {}

-- Obtiene el manejador para un lenguaje específico
-- @param filetype string: Tipo de archivo
-- @return tabla|nil: Módulo manejador del lenguaje o nil si no está soportado
function M._get_language_handler(filetype)
  -- Si ya hemos cargado este manejador, devolverlo
  if M.handlers[filetype] then
    return M.handlers[filetype]
  end

  -- Casos especiales para filetypes que necesitan un manejador específico
  -- pero podrían estar bajo otro nombre
  if filetype == "ex" or filetype == "exs" then
    filetype = "elixir"  -- Asegurar que se use el manejador de Elixir para archivos .ex y .exs
  elseif filetype == "jsx" or filetype == "tsx" then
    -- Para JSX/TSX, intentar cargar sus manejadores específicos primero
    local specific_handler_path = "copilotchatassist.documentation.language." .. filetype
    local specific_ok, specific_handler = pcall(require, specific_handler_path)
    if specific_ok and specific_handler then
      M.handlers[filetype] = specific_handler
      return specific_handler
    end

    -- Si no hay manejador específico, usar javascript/typescript
    filetype = filetype == "jsx" and "javascript" or "typescript"
  end

  local handler_path = "copilotchatassist.documentation.language." .. filetype

  local ok, handler = pcall(require, handler_path)
  if not ok then
    -- Intentar cargar el manejador común
    handler_path = "copilotchatassist.documentation.language.common"
    ok, handler = pcall(require, handler_path)
    if not ok then
      return nil
    end
  end

  -- Guardar en caché para uso futuro
  M.handlers[filetype] = handler

  return handler
end

-- Comprueba si una función tiene documentación
-- @param buffer número: ID del buffer
-- @param start_line número: Línea de inicio de la función
-- @param end_line número: Línea de fin de la función
-- @return boolean: true si tiene documentación, false en caso contrario
function M.has_documentation(buffer, start_line, end_line)
  local filetype = vim.bo[buffer].filetype
  local handler = M._get_language_handler(filetype)

  if not handler then
    return false
  end

  return handler.has_documentation(buffer, start_line, end_line)
end

-- Determina si la documentación de una función está desactualizada
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param func_lines tabla: Líneas de la función
-- @return boolean: true si está desactualizada, false en caso contrario
function M.is_documentation_outdated(buffer, doc_lines, func_lines)
  local filetype = vim.bo[buffer].filetype
  local handler = M._get_language_handler(filetype)

  if not handler then
    return false
  end

  return handler.is_documentation_outdated(buffer, doc_lines, func_lines)
end

-- Exportar constantes
M.ISSUE_TYPES = ISSUE_TYPES

return M