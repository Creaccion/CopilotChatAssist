-- Módulo para validación robusta de respuestas de CopilotChat
-- Proporciona funciones para validar y extraer contenido de diferentes formatos de respuesta

local M = {}

local log = require("copilotchatassist.utils.log")

-- Validar una respuesta y extraer contenido válido
-- Retorna el contenido validado o nil si no es válido
function M.validate_response(response, min_length)
  min_length = min_length or 10  -- Longitud mínima por defecto
  
  -- Registrar información de la respuesta
  log.debug("Validando respuesta de tipo: " .. type(response))
  
  -- Si es nil, no hay respuesta
  if response == nil then
    log.error("Respuesta nil recibida")
    return nil
  end
  
  -- Si es string, validar longitud
  if type(response) == "string" then
    if #response >= min_length then
      log.debug("Respuesta string válida, longitud: " .. #response)
      return response
    else
      log.error("Respuesta string demasiado corta: " .. #response .. " caracteres")
      return nil
    end
  end
  
  -- Si es tabla, intentar extraer contenido
  if type(response) == "table" then
    -- Guardar respuesta completa para depuración
    local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    vim.fn.mkdir(debug_dir, "p")
    local debug_file = debug_dir .. "/response_validator_input.txt"
    local file = io.open(debug_file, "w")
    if file then
      local ok, str = pcall(vim.inspect, response)
      file:write(ok and str or "Error serializing response")
      file:close()
      log.debug("Respuesta original guardada en: " .. debug_file)
    end
    
    -- Verificar los campos más comunes primero
    local content = nil
    
    -- Orden de búsqueda priorizado
    if response.content and type(response.content) == "string" then
      content = response.content
      log.debug("Contenido encontrado en campo 'content', longitud: " .. #content)
    elseif response.text and type(response.text) == "string" then
      content = response.text
      log.debug("Contenido encontrado en campo 'text', longitud: " .. #content)
    elseif response.message and type(response.message) == "string" then
      content = response.message
      log.debug("Contenido encontrado en campo 'message', longitud: " .. #content)
    elseif response[1] and type(response[1]) == "string" then
      content = response[1]
      log.debug("Contenido encontrado en índice [1], longitud: " .. #content)
    else
      -- Búsqueda más exhaustiva
      -- 1. Buscar cualquier campo de string largo
      for k, v in pairs(response) do
        if type(v) == "string" and #v >= min_length then
          content = v
          log.debug("Contenido encontrado en campo '" .. k .. "', longitud: " .. #content)
          break
        end
      end
      
      -- 2. Si no se encontró contenido, buscar en campos anidados
      if not content then
        for k, v in pairs(response) do
          if type(v) == "table" then
            -- Revisar campo 'content' anidado
            if v.content and type(v.content) == "string" and #v.content >= min_length then
              content = v.content
              log.debug("Contenido encontrado en campo '" .. k .. ".content', longitud: " .. #content)
              break
            end
            
            -- Revisar otros campos anidados
            for k2, v2 in pairs(v) do
              if type(v2) == "string" and #v2 >= min_length then
                content = v2
                log.debug("Contenido encontrado en campo '" .. k .. "." .. k2 .. "', longitud: " .. #content)
                break
              end
            end
          end
        end
      end
    end
    
    -- Si se encontró contenido, verificar longitud
    if content and #content >= min_length then
      log.debug("Contenido extraído válido, longitud: " .. #content)
      return content
    else
      log.error("No se pudo extraer contenido válido de la respuesta o es demasiado corto")
      return nil
    end
  end
  
  -- Si no es ni string ni tabla, no es un formato válido
  log.error("Formato de respuesta no soportado: " .. type(response))
  return nil
end

-- Limpiar formato del contenido extraído
function M.clean_content(content)
  if not content then return nil end
  
  -- Quitar backticks de código al inicio y final
  if content:match("^```") and content:match("```%s*$") then
    content = content:gsub("^```[^\n]*\n?", ""):gsub("\n?```%s*$", "")
    log.debug("Limpieza: eliminados backticks de bloque de código")
  end
  
  -- Eliminar espacios en blanco al principio y final
  content = content:gsub("^%s+", ""):gsub("%s+$", "")
  
  return content
end

-- Función principal para procesar respuestas
-- Valida, extra contenido y limpia formato
function M.process_response(response, min_length)
  local content = M.validate_response(response, min_length)
  
  if not content then
    return nil
  end
  
  return M.clean_content(content)
end

return M