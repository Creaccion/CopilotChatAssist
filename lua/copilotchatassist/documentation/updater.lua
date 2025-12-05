-- Módulo para actualizar documentación existente
-- Se encarga de actualizar la documentación cuando está desactualizada o incompleta

local M = {}
local log = require("copilotchatassist.utils.log")
local utils = require("copilotchatassist.documentation.utils")
-- Cargar copilot_api de manera perezosa para evitar dependencias circulares

-- Actualiza la documentación de un elemento específico
-- @param item tabla: Información del elemento a actualizar
-- @return boolean: true si se inició la actualización, false en caso contrario
function M.update_documentation(item)
  -- Verificar datos mínimos requeridos
  if not item or not item.bufnr or not item.start_line or not item.doc_lines then
    log.error("Información insuficiente para actualizar documentación")
    return false
  end

  -- Obtener el filetype para determinar el estilo de documentación
  local filetype = vim.bo[item.bufnr].filetype
  local handler = require("copilotchatassist.documentation.detector")._get_language_handler(filetype)

  if not handler then
    log.error("No hay manejador disponible para el lenguaje: " .. filetype)
    return false
  end

  -- Generar prompt para CopilotChat
  local prompt = M._create_update_prompt(item, filetype)

  log.debug("Solicitando actualización de documentación para " .. item.name)
  vim.notify("Actualizando documentación para " .. item.name .. "...", vim.log.levels.INFO)

  -- Llamar a CopilotChat (carga perezosa para evitar dependencia circular)
  local ok, copilot_api = pcall(require, "copilotchatassist.copilotchat_api")
  if not ok then
    log.error("Error al cargar copilotchat_api: " .. tostring(copilot_api))
    vim.notify("No se pudo cargar el módulo CopilotChat API", vim.log.levels.ERROR)
    return false
  end

  copilot_api.ask(prompt, {
    headless = true,
    callback = function(response)
      M._process_update_response(response, item, handler)
    end
  })

  return true
end

-- Crea el prompt para solicitar actualización de documentación
-- @param item tabla: Información del elemento a actualizar
-- @param filetype string: Tipo de archivo
-- @return string: Prompt para CopilotChat
function M._create_update_prompt(item, filetype)
  -- Convertir las líneas de documentación existentes a texto
  local existing_doc = table.concat(item.doc_lines, "\n")

  -- Obtener contexto adicional si está disponible
  local context = utils.get_function_context(item.bufnr, item.start_line, item.end_line)

  -- Base del prompt
  local prompt = [[
Por favor, actualiza la documentación para la siguiente función/clase.

Documentación existente:
```]] .. filetype .. [[
]] .. existing_doc .. [[
```

Código a documentar:
```]] .. filetype .. [[
]] .. item.content .. [[
```
]]

  -- Añadir contexto si está disponible
  if context and context ~= "" then
    prompt = prompt .. [[

Contexto adicional:
```]] .. filetype .. [[
]] .. context .. [[
```
]]
  end

  -- Añadir instrucciones específicas según el problema
  if item.issue_type == "outdated" then
    prompt = prompt .. [[

La documentación está desactualizada. Específicamente:
1. Hay cambios en la implementación que no se reflejan en la documentación
2. Actualiza la descripción, parámetros, tipos y valores de retorno según sea necesario
3. Mantén el mismo estilo y formato de la documentación original
]]
  elseif item.issue_type == "incomplete" then
    prompt = prompt .. [[

La documentación está incompleta. Específicamente:
1. Faltan documentar algunos parámetros o valores de retorno
2. Completa la documentación manteniendo el mismo estilo y formato
3. Asegúrate de incluir todos los parámetros y valores de retorno
]]
  end

  -- Instrucciones generales
  prompt = prompt .. [[

Requisitos para la actualización:
1. Mantén el formato de documentación existente
2. Asegúrate de que la documentación refleje con precisión la implementación actual
3. Documenta todos los parámetros, incluyendo tipos si es posible inferirlos
4. Documenta los valores de retorno, incluyendo tipos
5. Menciona cualquier excepción o error que pueda lanzar
6. NO incluyas comentarios adicionales dentro del cuerpo de la función
7. Devuelve SOLO el bloque de documentación actualizado, sin el código original

Genera solo el bloque de documentación actualizado que debería insertarse en lugar de la documentación actual.
]]

  return prompt
end

-- Procesa la respuesta de CopilotChat y aplica la documentación actualizada
-- @param response string|table: Respuesta de CopilotChat
-- @param item tabla: Información del elemento
-- @param handler tabla: Manejador del lenguaje
function M._process_update_response(response, item, handler)
  log.debug("Procesando respuesta de actualización para " .. item.name)

  -- Manejar diferentes formatos de respuesta
  local response_text = ""
  if type(response) == "table" then
    log.debug("Respuesta recibida como tabla")
    response_text = response.content or ""
  elseif type(response) == "string" then
    log.debug("Respuesta recibida como string")
    response_text = response
  else
    log.error("Formato de respuesta desconocido: " .. type(response))
    vim.notify("Error: formato de respuesta inesperado de CopilotChat", vim.log.levels.ERROR)
    return
  end

  if response_text == "" then
    log.error("Respuesta de actualización de CopilotChat vacía")
    vim.notify("No se pudo generar la actualización de documentación", vim.log.levels.ERROR)
    return
  end

  log.debug("Longitud de la respuesta de actualización: " .. #response_text .. " caracteres")

  -- Extraer el bloque de documentación
  local doc_block = utils.extract_documentation_from_response(response_text)

  if not doc_block or doc_block == "" then
    log.error("No se pudo extraer documentación válida de la respuesta de actualización")
    vim.notify("La respuesta no contiene un bloque de documentación válido", vim.log.levels.ERROR)
    log.debug("Primeros 100 caracteres de la respuesta: " .. string.sub(response_text, 1, 100))
    return
  end

  log.debug("Documentación de actualización extraída con éxito: " .. #doc_block .. " caracteres")

  -- Validar la documentación extraída
  local filetype = vim.bo[item.bufnr].filetype
  if utils.validate_documentation and not utils.validate_documentation(doc_block, filetype) then
    log.error("La documentación actualizada no parece válida")
    vim.notify("La documentación actualizada no cumple con los requisitos de formato", vim.log.levels.ERROR)

    -- Intentar recuperar solo los comentarios de la respuesta
    if filetype == "lua" then
      local lua_comments = {}
      for line in response_text:gmatch("[^\r\n]+") do
        if line:match("^%s*%-%-") then
          table.insert(lua_comments, line)
        end
      end

      if #lua_comments > 0 then
        doc_block = table.concat(lua_comments, "\n")
        log.debug("Recuperados " .. #lua_comments .. " comentarios Lua de la respuesta")
      else
        return
      end
    else
      return
    end
  end

  -- Aplicar la documentación al buffer
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(item.bufnr) then
      log.error("El buffer ya no es válido")
      return
    end

    -- Comparar la documentación existente con la generada
    local existing_doc = table.concat(item.doc_lines, "\n")
    if existing_doc == doc_block then
      vim.notify("La documentación generada es idéntica a la existente", vim.log.levels.INFO)
      return
    end

    -- Si la diferencia de tamaño es significativa, alertar
    local size_diff = math.abs(#existing_doc - #doc_block)
    if size_diff > #existing_doc * 0.5 then  -- Diferencia mayor al 50%
      log.warn("La nueva documentación tiene una diferencia de tamaño significativa: " .. #existing_doc .. " vs " .. #doc_block)

      -- Si la nueva es mucho más pequeña y la original tiene cierto tamaño, posible pérdida
      if #doc_block < #existing_doc * 0.5 and #existing_doc > 100 then
        log.warn("La nueva documentación es considerablemente más pequeña que la original")
        vim.notify("Advertencia: La actualización es mucho más pequeña que la documentación original", vim.log.levels.WARN)

        -- Verificar que contiene al menos los marcadores esenciales
        local has_essential = false
        if item.params and #item.params > 0 then
          for _, param in ipairs(item.params) do
            if doc_block:match("@param%s+" .. param) then
              has_essential = true
              break
            end
          end

          if not has_essential then
            log.error("La nueva documentación no contiene los parámetros esenciales")
            vim.notify("Error: La documentación actualizada no incluye los parámetros necesarios", vim.log.levels.ERROR)
            return
          end
        end
      end
    end

    log.debug("Actualizando documentación para " .. item.name)

    -- Hacer una copia de seguridad del contenido original
    local backup_start = math.max(1, item.doc_start_line - 3)
    local buffer_line_count = vim.api.nvim_buf_line_count(item.bufnr)
    local backup_end = math.min(buffer_line_count, item.end_line + 3)
    local backup_lines = vim.api.nvim_buf_get_lines(item.bufnr, backup_start - 1, backup_end, false)

    -- Usar el manejador específico del lenguaje para aplicar la actualización
    local success = handler.update_documentation(item.bufnr, item.doc_start_line, item.doc_end_line, doc_block)

    if success then
      -- Verificar integridad después de la actualización
      local original_function_line = vim.api.nvim_buf_get_lines(item.bufnr, item.start_line - 1, item.start_line, false)[1]
      local new_lines = vim.api.nvim_buf_get_lines(item.bufnr, backup_start - 1, backup_end, false)

      local function_preserved = false
      for _, line in ipairs(new_lines) do
        if line == original_function_line then
          function_preserved = true
          break
        end
      end

      if not function_preserved and original_function_line and original_function_line:match("%S") then
        log.error("Se detectó pérdida de la línea de función. Restaurando backup...")
        vim.api.nvim_buf_set_lines(item.bufnr, backup_start - 1, backup_start - 1 + #new_lines, false, backup_lines)
        vim.notify("Error: Se detectó una posible pérdida de código. Se restauró el estado anterior.", vim.log.levels.ERROR)
        return
      end

      vim.notify("Documentación actualizada correctamente para " .. item.name, vim.log.levels.INFO)
      log.debug("Documentación actualizada con éxito")
    else
      vim.notify("Error al actualizar la documentación", vim.log.levels.ERROR)
      log.error("No se pudo actualizar la documentación")
    end
  end)
end

-- Actualiza todas las documentaciones desactualizadas en un buffer
-- @param buffer número: ID del buffer
-- @return number: Número de elementos actualizados
function M.update_all_outdated(buffer)
  local detector = require("copilotchatassist.documentation.detector")
  local items = detector.scan_buffer(buffer)

  -- Filtrar solo los elementos con documentación desactualizada o incompleta
  local outdated_docs = {}
  for _, item in ipairs(items) do
    if item.issue_type == detector.ISSUE_TYPES.OUTDATED or
       item.issue_type == detector.ISSUE_TYPES.INCOMPLETE then
      table.insert(outdated_docs, item)
    end
  end

  if #outdated_docs == 0 then
    vim.notify("No se encontraron documentaciones desactualizadas", vim.log.levels.INFO)
    return 0
  end

  -- Procesar cada elemento
  for i, item in ipairs(outdated_docs) do
    log.debug("Actualizando documentación para elemento " .. i .. "/" .. #outdated_docs)
    M.update_documentation(item)

    -- Esperar un poco entre solicitudes para no sobrecargar
    if i < #outdated_docs then
      vim.defer_fn(function() end, 1000)
    end
  end

  return #outdated_docs
end

-- Fusiona documentación existente con actualizaciones
-- @param existing_doc string: Documentación existente
-- @param updated_doc string: Documentación actualizada
-- @param filetype string: Tipo de archivo
-- @return string: Documentación fusionada
function M.merge_documentation(existing_doc, updated_doc, filetype)
  if not existing_doc or existing_doc == "" then
    return updated_doc
  end

  if not updated_doc or updated_doc == "" then
    return existing_doc
  end

  -- Intentar usar el manejador específico del lenguaje para la fusión
  local handler = require("copilotchatassist.documentation.detector")._get_language_handler(filetype)
  if handler and handler.merge_documentation then
    return handler.merge_documentation(existing_doc, updated_doc)
  end

  -- Implementación por defecto: reemplazar completamente
  return updated_doc
end

return M