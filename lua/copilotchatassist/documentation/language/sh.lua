-- Manejador específico para documentación de shell scripts (bash, sh)
-- Extiende el manejador común con funcionalidades específicas para shell

local M = {}
local common = require("copilotchatassist.documentation.language.common")
local log = require("copilotchatassist.utils.log")

-- Heredar funcionalidad básica del manejador común
for k, v in pairs(common) do
  M[k] = v
end

-- Sobreescribir patrones para adaptarlos a shell scripts
M.patterns = {
  -- Patrones específicos para shell scripts
  function_start = "^%s*function%s+([%w_-]+)%s*%(?%)?%s*{",
  alt_function_start = "^%s*([%w_-]+)%s*%(%)%s*{",
  function_end = "^%s*}",
  comment_start = "^%s*#%s*",
  block_comment_start = "^%s*<<['\"]-?EOC['\"]-?",
  block_comment_end = "^%s*EOC",
}

-- Encuentra la línea de finalización de una función en shell
-- @param lines tabla: Líneas del buffer
-- @param start_line número: Línea de inicio
-- @param item_type string: Tipo de elemento ("function")
-- @return número: Número de línea final o nil si no se puede determinar
function M.find_end_line(lines, start_line, item_type)
  if not lines or not start_line or start_line > #lines then
    return nil
  end

  local bracket_depth = 0

  -- En scripts de shell, buscamos la llave de cierre correspondiente
  for i = start_line, #lines do
    local line = lines[i]

    -- Saltar líneas de comentario
    if line:match("^%s*#") then
      goto continue
    end

    -- Buscar llaves y manejar niveles de anidamiento
    for j = 1, #line do
      local char = line:sub(j, j)

      -- Ignoramos caracteres en comentarios
      if line:sub(j):match("^#") then
        break  -- Ignorar resto de la línea
      end

      if char == "{" then
        bracket_depth = bracket_depth + 1
      elseif char == "}" then
        bracket_depth = bracket_depth - 1
        if bracket_depth == 0 then
          return i
        end
      end
    end

    -- Búsqueda alternativa para funciones terminadas con "}"
    if bracket_depth == 0 and line:match(M.patterns.function_end) then
      return i
    end

    ::continue::
  end

  return #lines  -- Si no se puede determinar, devolver la última línea
end

-- Busca documentación en líneas de texto para shell scripts
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

  -- Buscar comentarios justo antes de la función
  local doc_end = start_idx - 1
  local doc_start = nil
  local in_block_comment = false
  local doc_lines = {}

  for i = doc_end, min_idx, -1 do
    local line = lines[i]

    -- Saltarse líneas vacías inmediatas
    if not doc_start and line:match("^%s*$") then
      doc_end = i - 1
      goto continue
    end

    -- Detectar comentarios de shell (línea simple o bloque)
    local is_comment_line = line:match("^%s*#")
    local is_block_end = line:match(M.patterns.block_comment_end)
    local is_block_start = line:match(M.patterns.block_comment_start)

    if is_block_end then
      in_block_comment = true
    end

    if is_comment_line or in_block_comment then
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
      in_block_comment = false
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

-- Escanea un buffer en busca de problemas de documentación en shell scripts
-- @param buffer número: ID del buffer a escanear
-- @return tabla: Lista de elementos con problemas de documentación
function M.scan_buffer(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local items = {}
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  -- Buscar definiciones de funciones en shell scripts
  for i, line in ipairs(lines) do
    -- Omitir líneas de comentario en esta fase
    if line:match("^%s*#") then
      goto continue
    end

    -- Variable para almacenar el nombre de la función
    local func_name = nil
    local func_type = "function"

    -- Función estándar
    func_name = line:match(M.patterns.function_start)

    -- Función alternativa (sin palabra clave 'function')
    if not func_name then
      func_name = line:match(M.patterns.alt_function_start)
    end

    -- Si se encontró una función, procesarla
    if func_name then
      log.debug("Función detectada: " .. func_name .. " en línea " .. i)

      -- Encontrar el final de la función
      local end_line = M.find_end_line(lines, i, func_type)
      if not end_line then
        -- Si no se puede determinar el final, usar una estimación
        end_line = i + 10  -- Asumimos que la función tiene al menos 10 líneas
      end

      -- Verificar si tiene documentación
      local doc_info = M.find_doc_block(lines, i)
      local has_doc = doc_info ~= nil

      -- Contenido de la función
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
        -- Para scripts de shell, consideramos que la documentación está completa si existe
        -- No implementamos verificación de parámetros por ahora
        issue_type = nil
      end

      -- Si hay un problema, agregar a la lista
      if issue_type then
        table.insert(items, {
          name = func_name,
          type = func_type,
          bufnr = buffer,
          start_line = i,
          end_line = end_line,
          content = content,
          has_doc = has_doc,
          issue_type = issue_type,
          doc_start_line = has_doc and doc_info.start_line or nil,
          doc_end_line = has_doc and doc_info.end_line or nil,
          doc_lines = has_doc and doc_info.lines or nil,
          params = {}  -- Shell no tiene parámetros formales
        })
      end
    end

    ::continue::
  end

  log.debug("Se encontraron " .. #items .. " elementos con problemas de documentación en el shell script")
  return items
end

-- Determina si la documentación de una función está desactualizada
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param func_lines tabla: Líneas de la función
-- @return boolean: true si está desactualizada, false en caso contrario
function M.is_documentation_outdated(buffer, doc_lines, func_lines)
  -- Para shell scripts, no implementamos verificación detallada de actualización
  -- Simplemente asumimos que está actualizada si existe
  return false
end

-- Determina si la documentación de una función está incompleta
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param param_names tabla: Nombres de los parámetros
-- @return boolean: true si está incompleta, false en caso contrario
function M.is_documentation_incomplete(buffer, doc_lines, param_names)
  -- Para shell scripts, no implementamos verificación detallada de completitud
  -- Simplemente asumimos que está completa si existe
  return false
end

-- Normaliza la documentación para shell scripts
-- @param doc_block string: Bloque de documentación
-- @return string: Documentación normalizada
function M.normalize_documentation(doc_block)
  if not doc_block or doc_block == "" then
    return ""
  end

  -- Eliminar líneas vacías al inicio y al final
  doc_block = doc_block:gsub("^%s*(.-)%s*$", "%1")

  -- Asegurar que la documentación tenga el formato correcto para shell scripts
  local lines = vim.split(doc_block, "\n")
  local normalized_lines = {}

  for _, line in ipairs(lines) do
    -- Asegurar que cada línea comience con #
    if not line:match("^%s*#") and line:match("%S") then
      line = "# " .. line
    end
    table.insert(normalized_lines, line)
  end

  return table.concat(normalized_lines, "\n")
end

-- Aplica documentación a una función en shell script
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

  -- Asegurar que la documentación esté en formato de shell script
  doc_block = M.normalize_documentation(doc_block)

  -- Convertir a líneas
  local doc_lines = vim.split(doc_block, "\n")

  -- Verificaciones de seguridad
  if not vim.api.nvim_buf_is_valid(buffer) then
    log.error("Buffer inválido al aplicar documentación")
    return false
  end

  -- Verificar que start_line está dentro del rango del buffer
  local buffer_line_count = vim.api.nvim_buf_line_count(buffer)
  if start_line <= 0 or start_line > buffer_line_count + 1 then
    log.error("Línea de inicio fuera de rango: " .. start_line .. " (total líneas: " .. buffer_line_count .. ")")
    return false
  end

  -- Obtener la línea de destino para la indentación
  local target_line = ""
  if start_line <= buffer_line_count then
    local lines = vim.api.nvim_buf_get_lines(buffer, start_line - 1, start_line, false)
    target_line = lines[1] or ""

    -- Verificar que la línea de destino contiene código real (no solo comentarios o espacios)
    if target_line:match("^%s*$") or target_line:match("^%s*#") then
      log.warn("La línea de destino parece vacía o un comentario. Verificando contexto...")

      -- Verificar las siguientes líneas para asegurarse de que estamos antes de código real
      local found_code = false
      for i = start_line, math.min(start_line + 5, buffer_line_count) do
        local check_line = vim.api.nvim_buf_get_lines(buffer, i - 1, i, false)[1] or ""
        if check_line:match("%S") and not check_line:match("^%s*#") then
          found_code = true
          break
        end
      end

      if not found_code then
        log.error("No se encontró código válido después de la línea de destino. Posible posición incorrecta.")
        return false
      end
    end
  end

  local indent = target_line:match("^(%s*)")

  -- Aplicar indentación a las líneas de documentación
  for i, line in ipairs(doc_lines) do
    if line ~= "" then
      doc_lines[i] = indent .. line
    end
  end

  log.debug("Insertando documentación de " .. #doc_lines .. " líneas antes de la línea " .. start_line)

  -- Guardar la línea de destino para verificar después
  local target_line_content = target_line

  -- Crear una copia de seguridad de las líneas circundantes
  local backup_start = math.max(1, start_line - 5)
  local backup_end = math.min(buffer_line_count, start_line + 5)
  local backup_lines = vim.api.nvim_buf_get_lines(buffer, backup_start - 1, backup_end, false)
  local backup_info = {
    start_line = backup_start,
    end_line = backup_end,
    lines = backup_lines
  }

  -- Insertar la documentación (añadir línea en blanco al final si no existe)
  if #doc_lines > 0 and doc_lines[#doc_lines] ~= "" then
    table.insert(doc_lines, "")  -- Añadir línea en blanco para separar de la función
  end

  -- Insertar la documentación sin reemplazar nada (modo seguro)
  vim.api.nvim_buf_set_lines(buffer, start_line - 1, start_line - 1, false, doc_lines)

  -- Verificar que la línea de destino sigue siendo la misma (no se borró código)
  if start_line <= buffer_line_count then
    local new_line_index = start_line + #doc_lines - 1
    if new_line_index <= vim.api.nvim_buf_line_count(buffer) then
      local new_target_line = vim.api.nvim_buf_get_lines(buffer, new_line_index - 1, new_line_index, false)[1] or ""
      if new_target_line ~= target_line_content and target_line_content:match("%S") then
        log.error("¡Advertencia! La línea de destino ha cambiado después de la inserción. Posible pérdida de código.")
        log.error("Original: '" .. target_line_content .. "'")
        log.error("Nueva: '" .. new_target_line .. "'")

        -- Si parece que se eliminó código importante, restaurar el estado original
        if target_line_content:match("[%w_]") and not new_target_line:match("[%w_]") then
          log.warn("Detectada posible pérdida de código importante. Restaurando estado original...")
          vim.api.nvim_buf_set_lines(buffer, backup_info.start_line - 1, backup_info.start_line - 1 + #backup_info.lines, false, backup_info.lines)
          vim.notify("Se detectó un problema al insertar documentación. Se ha restaurado el estado anterior para evitar pérdida de código.", vim.log.levels.WARN)
          return false
        end
      end
    else
      log.error("La posición esperada de la línea de destino está fuera del buffer después de la inserción")
    end
  end

  return true
end

-- Encuentra ejemplos de documentación en el buffer
-- @param buffer número: ID del buffer
-- @param max_examples número: Máximo número de ejemplos a encontrar
-- @return tabla: Lista de ejemplos de documentación encontrados
function M.find_documentation_examples(buffer, max_examples)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local examples = {}
  max_examples = max_examples or 3

  for i = 1, #lines - 1 do
    local line = lines[i]

    -- Buscar inicio de bloque de comentarios
    if line:match("^%s*#") then
      local doc_start = i
      local doc_end = i
      local comment_block = { line }

      -- Buscar líneas consecutivas de comentarios
      for j = i + 1, math.min(i + 20, #lines) do
        if lines[j]:match("^%s*#") then
          table.insert(comment_block, lines[j])
          doc_end = j
        else
          break  -- Terminar si encontramos una línea que no es comentario
        end
      end

      -- Si el bloque es lo suficientemente largo y tiene alguna descripción útil
      if #comment_block >= 3 then
        local block_text = table.concat(comment_block, "\n")
        if block_text:match("[Pp]arameter") or
           block_text:match("[Rr]eturn") or
           block_text:match("[Dd]escription") or
           block_text:match("[Uu]sage") then
          table.insert(examples, block_text)

          if #examples >= max_examples then
            break
          end
        end
      end

      i = doc_end  -- Saltar al final del bloque
    end
  end

  return examples
end

return M