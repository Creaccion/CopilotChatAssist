-- Manejador común para documentación de código
-- Implementa funcionalidades genéricas que pueden ser extendidas por manejadores específicos

local M = {}
local log = require("copilotchatassist.utils.log")

-- Patrones comunes para detectar funciones y clases
M.patterns = {
  function_start = "function%s*([%w_%.:%[%]\"']+)%s*%((.-)%)",
  class_start = "class%s+([%w_]+)",
  comment_start = "^%s*[%-%/][%-%/]%s*",
  block_comment_start = "^%s*/[*]",
  block_comment_end = "[*]/%s*$",
}

-- Busca documentación en líneas de texto
-- @param lines tabla: Líneas de texto a analizar
-- @param start_idx número: Índice de inicio para la búsqueda
-- @param max_lines número: Máximo de líneas a buscar hacia atrás
-- @return tabla: Información de la documentación o nil si no se encuentra
function M.find_doc_block(lines, start_idx, max_lines)
  if not lines or not start_idx or start_idx < 1 or #lines < start_idx then
    return nil
  end

  max_lines = max_lines or 20
  local min_idx = math.max(1, start_idx - max_lines)

  -- Buscar comentarios justo antes de la función/clase
  local doc_end = start_idx - 1
  local doc_start = nil
  local in_comment_block = false
  local doc_lines = {}

  for i = doc_end, min_idx, -1 do
    local line = lines[i]

    -- Saltarse líneas vacías inmediatas
    if not doc_start and line:match("^%s*$") then
      doc_end = i - 1
      goto continue
    end

    -- Detectar inicio/fin de bloques de comentarios
    local is_comment_line = line:match(M.patterns.comment_start) ~= nil
    local is_block_start = line:match(M.patterns.block_comment_start) ~= nil
    local is_block_end = line:match(M.patterns.block_comment_end) ~= nil

    if is_block_end then
      in_comment_block = true
    end

    if is_comment_line or in_comment_block then
      if not doc_start then
        doc_start = i
      end
      table.insert(doc_lines, 1, line)
    else
      -- Si encontramos una línea que no es comentario ni parte de un bloque, terminamos
      if doc_start then
        break
      end
    end

    if is_block_start then
      in_comment_block = false
      break
    end

    ::continue::
  end

  if not doc_start or #doc_lines == 0 then
    return nil
  end

  return {
    start_line = doc_start,
    end_line = doc_end,
    lines = doc_lines,
    text = table.concat(doc_lines, "\n")
  }
end

-- Escanea un buffer completo en busca de problemas de documentación
-- @param buffer número: ID del buffer a escanear
-- @return tabla: Lista de elementos con problemas de documentación
function M.scan_buffer(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local items = {}
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  -- Buscar funciones y clases
  for i, line in ipairs(lines) do
    local func_name, params = line:match(M.patterns.function_start)
    local class_name = line:match(M.patterns.class_start)

    if func_name or class_name then
      local name = func_name or class_name
      local item_type = func_name and "function" or "class"

      -- Encontrar el final de la función/clase
      local end_line = M.find_end_line(lines, i, item_type)
      if not end_line then
        end_line = i + 1 -- Si no se puede determinar, asumimos que es la siguiente línea
      end

      -- Verificar si tiene documentación
      local doc_info = M.find_doc_block(lines, i)
      local has_doc = doc_info ~= nil

      -- Contenido de la función/clase
      local content_lines = {}
      for j = i, end_line do
        table.insert(content_lines, lines[j])
      end
      local content = table.concat(content_lines, "\n")

      -- Determinar tipo de problema
      local issue_type = nil
      if not has_doc then
        issue_type = issue_types.MISSING
      else
        -- Verificar si la documentación está desactualizada o incompleta
        -- Esto es específico del lenguaje, así que usamos una implementación básica
        local is_outdated = M.is_documentation_outdated(buffer, doc_info.lines, content_lines)
        if is_outdated then
          issue_type = issue_types.OUTDATED
        else
          local is_incomplete = M.is_documentation_incomplete(buffer, doc_info.lines, content_lines)
          if is_incomplete then
            issue_type = issue_types.INCOMPLETE
          end
        end
      end

      -- Si hay un problema, agregar a la lista
      if issue_type then
        table.insert(items, {
          name = name,
          type = item_type,
          bufnr = buffer,
          start_line = i,
          end_line = end_line,
          content = content,
          has_doc = has_doc,
          issue_type = issue_type,
          doc_start_line = has_doc and doc_info.start_line or nil,
          doc_end_line = has_doc and doc_info.end_line or nil,
          doc_lines = has_doc and doc_info.lines or nil
        })
      end
    end
  end

  return items
end

-- Encuentra la línea de finalización de una función o clase
-- @param lines tabla: Líneas del buffer
-- @param start_line número: Línea de inicio
-- @param item_type string: Tipo de elemento ("function" o "class")
-- @return número: Número de línea final o nil si no se puede determinar
function M.find_end_line(lines, start_line, item_type)
  if not lines or not start_line or start_line > #lines then
    return nil
  end

  local depth = 0
  local in_string = false
  local string_delim = nil

  -- Contar llaves para determinar el final del bloque
  for i = start_line, #lines do
    local line = lines[i]

    -- Procesar cada carácter para manejar correctamente las llaves y cadenas
    for j = 1, #line do
      local char = line:sub(j, j)
      local prev_char = j > 1 and line:sub(j-1, j-1) or ""

      -- Manejar cadenas para evitar confundir llaves dentro de cadenas
      if (char == "'" or char == "\"") and prev_char ~= "\\" then
        if not in_string then
          in_string = true
          string_delim = char
        elseif char == string_delim then
          in_string = false
          string_delim = nil
        end
      end

      -- Contar llaves solo si no estamos dentro de una cadena
      if not in_string then
        if char == "{" then
          depth = depth + 1
        elseif char == "}" then
          depth = depth - 1
          if depth == 0 then
            return i
          end
        end
      end
    end

    -- Para lenguajes que no usan llaves (como Python), buscar la indentación
    if item_type == "function" and depth == 0 then
      local current_indent = line:match("^(%s*)")

      -- Si estamos en la primera línea, obtener su indentación
      if i == start_line then
        base_indent = #current_indent
        goto continue
      end

      -- Si encontramos una línea con menor o igual indentación, consideramos que es el final
      if #current_indent <= base_indent and not line:match("^%s*$") then
        return i - 1
      end
    end

    ::continue::
  end

  return #lines -- Si no se puede determinar, devolver la última línea
end

-- Detecta un elemento documentable en una posición específica
-- @param buffer número: ID del buffer
-- @param row número: Número de fila (1-indexed)
-- @return tabla|nil: Información del elemento encontrado o nil si no se encuentra ninguno
function M.detect_at_position(buffer, row)
  local items = M.scan_buffer(buffer)

  for _, item in ipairs(items) do
    if row >= item.start_line and row <= item.end_line then
      return item
    end
  end

  return nil
end

-- Comprueba si una función tiene documentación
-- @param buffer número: ID del buffer
-- @param start_line número: Línea de inicio de la función
-- @param end_line número: Línea de fin de la función
-- @return boolean: true si tiene documentación, false en caso contrario
function M.has_documentation(buffer, start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local doc_info = M.find_doc_block(lines, start_line)

  return doc_info ~= nil
end

-- Determina si la documentación de una función está desactualizada
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param func_lines tabla: Líneas de la función
-- @return boolean: true si está desactualizada, false en caso contrario
function M.is_documentation_outdated(buffer, doc_lines, func_lines)
  -- Implementación básica
  -- Los manejadores específicos de lenguaje implementarán lógicas más sofisticadas
  return false
end

-- Determina si la documentación de una función está incompleta
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param func_lines tabla: Líneas de la función
-- @return boolean: true si está incompleta, false en caso contrario
function M.is_documentation_incomplete(buffer, doc_lines, func_lines)
  -- Implementación básica
  -- Los manejadores específicos de lenguaje implementarán lógicas más sofisticadas
  return false
end

-- Encuentra ejemplos de documentación en el buffer
-- @param buffer número: ID del buffer
-- @param max_examples número: Máximo número de ejemplos a encontrar
-- @return tabla: Lista de ejemplos de documentación encontrados
function M.find_documentation_examples(buffer, max_examples)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local examples = {}
  max_examples = max_examples or 3

  for i = 1, #lines do
    local line = lines[i]
    local is_function = line:match(M.patterns.function_start) ~= nil
    local is_class = line:match(M.patterns.class_start) ~= nil

    if is_function or is_class then
      local doc_info = M.find_doc_block(lines, i)
      if doc_info and #doc_info.lines >= 3 then
        table.insert(examples, table.concat(doc_info.lines, "\n"))

        if #examples >= max_examples then
          break
        end
      end
    end
  end

  return examples
end

-- Obtiene estadísticas de documentación para un buffer
-- @param buffer número: ID del buffer
-- @return tabla: Estadísticas de documentación
function M.get_doc_stats(buffer)
  local items = M.scan_buffer(buffer)
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  local stats = {
    total_items = #items,
    documented = 0,
    missing = 0,
    outdated = 0,
    incomplete = 0,
    coverage = 0
  }

  for _, item in ipairs(items) do
    if item.has_doc then
      stats.documented = stats.documented + 1

      if item.issue_type == issue_types.OUTDATED then
        stats.outdated = stats.outdated + 1
      elseif item.issue_type == issue_types.INCOMPLETE then
        stats.incomplete = stats.incomplete + 1
      end
    else
      stats.missing = stats.missing + 1
    end
  end

  if stats.total_items > 0 then
    stats.coverage = stats.documented / stats.total_items * 100
  end

  return stats
end

-- Aplica documentación a una función/clase
-- @param buffer número: ID del buffer
-- @param start_line número: Línea antes de la cual insertar la documentación
-- @param doc_block string: Bloque de documentación a insertar
-- @param item tabla: Información del elemento (opcional)
-- @return boolean: true si se aplicó correctamente, false en caso contrario
function M.apply_documentation(buffer, start_line, doc_block, item)
  if not doc_block or doc_block == "" then
    log.error("Bloque de documentación vacío")
    return false
  end

  -- Convertir a líneas
  local doc_lines = vim.split(doc_block, "\n")

  -- Obtener la indentación de la línea de destino
  local target_line = vim.api.nvim_buf_get_lines(buffer, start_line - 1, start_line, false)[1] or ""
  local indent = target_line:match("^(%s*)")

  -- Aplicar indentación a las líneas de documentación
  for i, line in ipairs(doc_lines) do
    if line ~= "" then
      doc_lines[i] = indent .. line
    end
  end

  -- Insertar la documentación
  vim.api.nvim_buf_set_lines(buffer, start_line - 1, start_line - 1, false, doc_lines)

  return true
end

-- Actualiza una documentación existente
-- @param buffer número: ID del buffer
-- @param doc_start_line número: Línea de inicio de la documentación
-- @param doc_end_line número: Línea de fin de la documentación
-- @param doc_block string: Nuevo bloque de documentación
-- @return boolean: true si se actualizó correctamente, false en caso contrario
function M.update_documentation(buffer, doc_start_line, doc_end_line, doc_block)
  if not doc_block or doc_block == "" then
    log.error("Bloque de documentación vacío")
    return false
  end

  -- Convertir a líneas
  local doc_lines = vim.split(doc_block, "\n")

  -- Obtener la indentación de la primera línea de la documentación existente
  local existing_line = vim.api.nvim_buf_get_lines(buffer, doc_start_line - 1, doc_start_line, false)[1] or ""
  local indent = existing_line:match("^(%s*)")

  -- Aplicar indentación a las líneas de documentación
  for i, line in ipairs(doc_lines) do
    if line ~= "" then
      doc_lines[i] = indent .. line
    end
  end

  -- Reemplazar la documentación existente
  vim.api.nvim_buf_set_lines(buffer, doc_start_line - 1, doc_end_line, false, doc_lines)

  return true
end

-- Normaliza el formato de documentación
-- @param doc_block string: Bloque de documentación
-- @return string: Documentación normalizada
function M.normalize_documentation(doc_block)
  if not doc_block or doc_block == "" then
    return ""
  end

  -- Eliminar líneas vacías al inicio y al final
  doc_block = doc_block:gsub("^%s*(.-)%s*$", "%1")

  return doc_block
end

-- Fusiona documentación existente con actualizaciones
-- @param existing_doc string: Documentación existente
-- @param updated_doc string: Documentación actualizada
-- @return string: Documentación fusionada
function M.merge_documentation(existing_doc, updated_doc)
  -- Implementación básica: reemplazar completamente
  return updated_doc
end

-- Valida que una documentación cumpla con requisitos mínimos
-- @param doc_block string: Bloque de documentación
-- @return boolean: true si la documentación es válida, false en caso contrario
function M.validate_documentation(doc_block)
  if not doc_block or doc_block == "" then
    return false
  end

  -- Verificar que tenga al menos una línea no vacía
  for line in doc_block:gmatch("[^\r\n]+") do
    if line:match("%S") then
      return true
    end
  end

  return false
end

return M