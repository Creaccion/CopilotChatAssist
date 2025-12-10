-- Módulo para generar nueva documentación para código existente
-- Usa CopilotChat para analizar y documentar código sin documentación

local M = {}
local log = require("copilotchatassist.utils.log")
local utils = require("copilotchatassist.documentation.utils")
-- Cargar copilot_api de manera perezosa para evitar dependencias circulares

-- Genera documentación para un elemento específico
-- @param item tabla: Información del elemento a documentar
-- @return boolean: true si se generó correctamente, false en caso contrario
function M.generate_documentation(item)
  -- Verificar datos mínimos requeridos
  if not item or not item.bufnr or not item.start_line or not item.end_line or not item.content then
    log.error("Información insuficiente para generar documentación")
    return false
  end

  -- Verificar que el buffer es válido
  if not pcall(vim.api.nvim_buf_is_valid, item.bufnr) or not vim.api.nvim_buf_is_valid(item.bufnr) then
    log.error("El buffer " .. tostring(item.bufnr) .. " no es válido o no existe")
    vim.notify("No se puede generar documentación: el buffer no es válido", vim.log.levels.ERROR)
    return false
  end

  -- Obtener el filetype para determinar el estilo de documentación
  local filetype
  local ok, result = pcall(function() return vim.bo[item.bufnr].filetype end)
  if not ok or not result then
    -- Si no podemos obtener el filetype del buffer, intentar deducirlo por el nombre del archivo
    filetype = utils.get_filetype_from_buffer(item.bufnr)
  else
    filetype = result
  end

  -- Si no hay filetype, abortar
  if not filetype then
    log.error("No se pudo determinar el tipo de archivo para el buffer " .. tostring(item.bufnr))
    vim.notify("No se puede generar documentación: tipo de archivo desconocido", vim.log.levels.ERROR)
    return false
  end

  -- Generar el contenido de la documentación
  local doc_content = M.generate_documentation_content(item)
  if not doc_content or doc_content == "" then
    log.error("No se pudo generar el contenido de documentación")
    vim.notify("No se pudo generar el contenido de documentación", vim.log.levels.ERROR)
    return false
  end

  -- Si estamos en modo previsualización, solo devolver true
  local documentation_module = require("copilotchatassist.documentation")
  if documentation_module.state.preview_mode then
    return true
  end

  -- Determinar dónde insertar la documentación
  local target_line = item.start_line
  if target_line <= 0 then
    log.error("Línea de inicio inválida: " .. tostring(target_line))
    return false
  end

  -- Verificar si el elemento tiene una línea de documentación determinada específicamente
  if item.doc_line and item.doc_line > 0 and item.doc_line < target_line then
    target_line = item.doc_line
  end

  -- Obtener indentación
  local indent_str
  local current_line = vim.api.nvim_buf_get_lines(item.bufnr, target_line - 1, target_line, false)[1] or ""
  indent_str = current_line:match("^%s+") or ""

  -- Aplicar indentación a las líneas de documentación
  local doc_lines = {}
  for line in doc_content:gmatch("[^\n]+") do
    table.insert(doc_lines, indent_str .. line)
  end

  -- Añadir una línea en blanco después de la documentación si es apropiado
  if #doc_lines > 0 and not doc_lines[#doc_lines]:match("^%s*$") then
    table.insert(doc_lines, indent_str)
  end

  -- Insertar documentación
  vim.api.nvim_buf_set_lines(item.bufnr, target_line - 1, target_line - 1, false, doc_lines)

  -- Registrar éxito
  log.info("Documentación generada para " .. (item.name or "elemento sin nombre") .. " en línea " .. target_line)
  return true
end

-- Genera sólo el contenido de la documentación sin aplicarlo
-- @param item tabla: Información del elemento a documentar
-- @return string: El contenido de la documentación generada o nil en caso de error
function M.generate_documentation_content(item)
  if not item then return nil end

  -- Determinar el tipo de elemento y filetype
  local filetype = vim.bo[item.bufnr].filetype
  if not filetype or filetype == "" then
    filetype = utils.get_filetype_from_buffer(item.bufnr)
    if not filetype then
      log.error("No se pudo determinar el tipo de archivo")
      return nil
    end
  end

  -- Seleccionar el estilo de documentación según el tipo de archivo
  local doc_style = utils.get_doc_style_for_filetype(filetype)
  if not doc_style then
    log.error("No hay estilo de documentación definido para el tipo de archivo: " .. filetype)
    return nil
  end

  -- Preparar el contexto para la documentación
  local element_content = item.content or ""
  local context_lines = utils.get_context_lines(item.bufnr, item.start_line, item.end_line, 10)
  local context = table.concat(context_lines, "\n")

  -- Cargar el módulo de CopilotChat API bajo demanda
  local copilotchat_api = require("copilotchatassist.copilotchat_api")

  -- Preparar el prompt para CopilotChat
  local prompt
  local element_type = item.type or "función"

  -- Construir prompt
  prompt = string.format(
    "Genera una documentación para la siguiente %s en %s.\n\n" ..
    "Código a documentar:\n```%s\n%s\n```\n\n" ..
    "Contexto adicional:\n```%s\n%s\n```\n\n" ..
    "Usa el siguiente estilo: %s\n\n" ..
    "La documentación debe ser concisa pero completa, incluyendo:\n" ..
    "- Descripción general\n" ..
    "- Parámetros (si aplica)\n" ..
    "- Valores de retorno (si aplica)\n" ..
    "- Excepciones o errores (si aplica)\n\n" ..
    "Proporciona SOLO el bloque de documentación, sin ningún otro texto o explicación.",
    element_type, filetype,
    filetype, element_content,
    filetype, context,
    doc_style
  )

  -- Variable para almacenar el resultado
  local result

  -- Hacer la llamada a CopilotChat y esperar la respuesta
  copilotchat_api.ask(prompt, {
    callback = function(response)
      if response then
        -- Limpiar posibles backticks de código
        response = response:gsub("```%w*\n", ""):gsub("```", "")

        -- Eliminar espacios en blanco extra al principio y final
        response = response:gsub("^%s*(.-)%s*$", "%1")

        result = response
      end
    end,
    system_prompt = "Eres un asistente especializado en generar documentación de código. Solo debes generar documentación sin añadir explicaciones adicionales. La documentación debe ser concisa pero completa.",
    sync = true  -- Esperar la respuesta antes de continuar
  })

  if not result or result == "" then
    log.error("No se recibió respuesta del generador de documentación")
    return nil
  end

  return result
end

-- Verificar si un elemento necesita documentación
-- @param item tabla: Elemento a verificar
-- @return boolean: true si necesita documentación, false en caso contrario
function M.needs_documentation(item)
  if not item or not item.bufnr or not item.start_line then
    return false
  end

  -- Si ya tiene un issue_type asignado, usar eso
  if item.issue_type then
    return item.issue_type == "missing"
  end

  -- Verificar manualmente si tiene documentación
  local bufnr = item.bufnr
  local start_line = item.start_line

  -- Verificar líneas anteriores
  local prev_lines = vim.api.nvim_buf_get_lines(bufnr, math.max(0, start_line - 5), start_line, false)
  for _, line in ipairs(prev_lines) do
    if line:match("/%*%*") or       -- Java/JS style /** */
       line:match("^%s*%-%-%-") or  -- Lua style ---
       line:match("^%s*#") or       -- Python/Ruby style #
       line:match("^%s*//") then    -- C++ style //
      return false  -- Tiene documentación
    end
  end

  return true  -- No tiene documentación
end

return M