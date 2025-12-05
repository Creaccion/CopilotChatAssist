-- Manejador específico para documentación de Lua
-- Extiende el manejador común con funcionalidades específicas para Lua

local M = {}
local common = require("copilotchatassist.documentation.language.common")
local log = require("copilotchatassist.utils.log")

-- Heredar funcionalidad básica del manejador común
for k, v in pairs(common) do
  M[k] = v
end

-- Sobreescribir patrones para adaptarlos a Lua
M.patterns = {
  -- Patrones específicos para Lua
  function_start = "function%s*([%w_%.:%[%]\"']+)%s*%(([^)]*)%)", -- Incluye métodos de tabla, locales, etc.
  method_start = "function%s*([%w_%.:%[%]\"']+):([%w_]+)%s*%(([^)]*)%)", -- Métodos con sintaxis de dos puntos
  local_function = "local%s+function%s+([%w_]+)%s*%(([^)]*)%)", -- Funciones locales
  module_function = "([%w_%.]+)%s*=%s*function%s*%(([^)]*)%)", -- Funciones asignadas (incluye M.funcion = function())
  anonymous_function = "=%s*function%s*%(([^)]*)%)", -- Funciones anónimas asignadas a variables
  class_start = nil, -- Lua no tiene sintaxis nativa para clases
  comment_start = "^%s*%-%-+%s*", -- Comentarios con --
  block_comment_start = "^%s*%-%-[%[]%[", -- Comentarios multilínea con --[[
  block_comment_end = "]]%s*$", -- Fin de comentario multilínea ]]
}

-- Encuentra la línea de finalización de una función en Lua
-- @param lines tabla: Líneas del buffer
-- @param start_line número: Línea de inicio
-- @param item_type string: Tipo de elemento ("function" o "table")
-- @return número: Número de línea final o nil si no se puede determinar
function M.find_end_line(lines, start_line, item_type)
  if not lines or not start_line or start_line > #lines then
    return nil
  end

  local depth = 0
  local in_string = false
  local string_delim = nil
  local in_comment = false
  local in_long_comment = false

  -- En Lua, buscamos la palabra clave "end" al mismo nivel de indentación
  for i = start_line, #lines do
    local line = lines[i]

    -- Saltar líneas de comentario
    if line:match("^%s*%-%-") then
      goto continue
    end

    -- Procesar cada carácter para detectar cadenas y bloques
    for j = 1, #line do
      local char = line:sub(j, j)
      local prev_char = j > 1 and line:sub(j-1, j-1) or ""
      local next_chars = j < #line - 1 and line:sub(j, j+1) or ""

      -- Detectar comentarios
      if next_chars == "--" and not in_string then
        in_comment = true
        break -- Ignorar el resto de la línea
      end

      -- Saltar caracteres si estamos en un comentario
      if in_comment then
        goto continue_char
      end

      -- Manejar cadenas para evitar confundir palabras clave dentro de cadenas
      if (char == "'" or char == "\"") and prev_char ~= "\\" then
        if not in_string then
          in_string = true
          string_delim = char
        elseif char == string_delim then
          in_string = false
          string_delim = nil
        end
        goto continue_char
      end

      -- Contar bloques solo si no estamos dentro de una cadena
      if not in_string then
        if line:match("^%s*function%s", j) or line:match("^%s*do%s", j) or line:match("^%s*then%s", j) or line:match("^%s*repeat%s", j) then
          depth = depth + 1
        elseif line:match("^%s*end%s", j) or line:match("^%s*until%s", j) then
          depth = depth - 1
          if depth == 0 then
            return i
          end
        end
      end

      ::continue_char::
    end

    in_comment = false -- Reiniciar para la siguiente línea

    ::continue::
  end

  return #lines -- Si no se puede determinar, devolver la última línea
end

-- Busca documentación en líneas de texto para Lua
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
  local in_comment_block = false
  local doc_lines = {}

  for i = doc_end, min_idx, -1 do
    local line = lines[i]

    -- Saltarse líneas vacías inmediatas
    if not doc_start and line:match("^%s*$") then
      doc_end = i - 1
      goto continue
    end

    -- Detectar comentarios de Lua
    local is_comment_line = line:match("^%s*%-%-%s") ~= nil or line:match("^%s*%-%-$") ~= nil
    local is_block_start = line:match("^%s*%-%-[%[]%[") ~= nil
    local is_block_end = line:match("]]%s*$") ~= nil

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

-- Escanea un buffer en busca de problemas de documentación en Lua
-- @param buffer número: ID del buffer a escanear
-- @return tabla: Lista de elementos con problemas de documentación
function M.scan_buffer(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local items = {}
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  -- Buscar definiciones de funciones en Lua (varios patrones)
  for i, line in ipairs(lines) do
    -- Omitir líneas de comentario en esta fase
    if line:match("^%s*%-%-") then
      goto continue
    end

    -- Variable para almacenar el nombre de la función y sus parámetros
    local func_name = nil
    local params = nil
    local func_type = "function"

    -- Función estándar
    func_name, params = line:match(M.patterns.function_start)
    if func_name and func_name:match("^_G%.") then
      -- Ignorar funciones globales _G.*
      func_name = nil
    end

    -- Método con sintaxis de dos puntos
    if not func_name then
      local parent_name, method_name, method_params = line:match(M.patterns.method_start)
      if parent_name and method_name then
        func_name = parent_name .. ":" .. method_name
        params = method_params
        func_type = "method"
      end
    end

    -- Función local
    if not func_name then
      func_name, params = line:match(M.patterns.local_function)
      if func_name then
        func_type = "local_function"
      end
    end

    -- Función asignada (incluye M.funcion = function())
    if not func_name then
      func_name, params = line:match(M.patterns.module_function)
      if func_name then
        func_type = "assigned_function"
      end
    end

    -- Si se encontró una función, procesarla
    if func_name then
      log.debug("Función detectada: " .. func_name .. " en línea " .. i)

      -- Encontrar el final de la función
      local end_line = M.find_end_line(lines, i, func_type)
      if not end_line then
        -- Si no se puede determinar el final, buscar la línea "end" más cercana
        for j = i + 1, math.min(i + 100, #lines) do
          if lines[j]:match("^%s*end%s*$") or lines[j]:match("^%s*end[%s,%)%]}]") then
            end_line = j
            break
          end
        end

        -- Si aún no se encuentra, usar una estimación
        if not end_line then
          end_line = i + 5 -- Asumimos que la función tiene al menos 5 líneas
        end
      end

      -- Verificar si tiene documentación
      local doc_info = M.find_doc_block(lines, i)
      local has_doc = doc_info ~= nil

      -- Extraer parámetros, limpiando espacios y valores por defecto
      local param_names = {}
      if params then
        for param in params:gmatch("([^,]+)") do
          -- Eliminar espacios y valores por defecto
          param = param:match("^%s*([^=]+)") or param
          param = param:match("^%s*(.-)%s*$") -- Eliminar espacios
          if param and param ~= "" then
            table.insert(param_names, param)
          end
        end
      end

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
        -- Verificar si la documentación está desactualizada o incompleta
        local is_outdated = M.is_documentation_outdated(buffer, doc_info.lines, content_lines)
        if is_outdated then
          issue_type = issue_types.OUTDATED
        else
          local is_incomplete = M.is_documentation_incomplete(buffer, doc_info.lines, param_names)
          if is_incomplete then
            issue_type = issue_types.INCOMPLETE
          end
        end
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
          params = param_names
        })
      end
    end

    ::continue::
  end

  log.debug("Se encontraron " .. #items .. " funciones con problemas de documentación en el archivo Lua")
  return items
end

-- Detecta un elemento documentable en una posición específica
-- @param buffer número: ID del buffer
-- @param row número: Número de fila (1-indexed)
-- @return tabla|nil: Información del elemento encontrado o nil si no se encuentra ninguno
function M.detect_at_position(buffer, row)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  -- Buscar hacia arriba hasta encontrar una definición de función
  local current_line = row
  local max_lines_to_check = 20
  local checked_lines = 0
  local func_line = nil

  -- Primero buscar si estamos dentro de una función
  while current_line > 0 and checked_lines < max_lines_to_check do
    local line = lines[current_line]

    -- Si encontramos el inicio de una función, guardar la línea
    if line and (
      line:match(M.patterns.function_start) or
      line:match(M.patterns.method_start) or
      line:match(M.patterns.local_function) or
      line:match(M.patterns.module_function)
    ) then
      func_line = current_line
      break
    end

    -- Si encontramos un "end", probablemente estamos fuera de la función actual
    if line and line:match("^%s*end%s*$") then
      break
    end

    current_line = current_line - 1
    checked_lines = checked_lines + 1
  end

  -- Si encontramos una línea que parece ser una función, analizarla
  if func_line then
    log.debug("Función potencial encontrada en línea " .. func_line)

    -- Variable para almacenar el nombre de la función y sus parámetros
    local line = lines[func_line]
    local func_name = nil
    local params = nil
    local func_type = "function"

    -- Función estándar
    func_name, params = line:match(M.patterns.function_start)

    -- Método con sintaxis de dos puntos
    if not func_name then
      local parent_name, method_name, method_params = line:match(M.patterns.method_start)
      if parent_name and method_name then
        func_name = parent_name .. ":" .. method_name
        params = method_params
        func_type = "method"
      end
    end

    -- Función local
    if not func_name then
      func_name, params = line:match(M.patterns.local_function)
      if func_name then
        func_type = "local_function"
      end
    end

    -- Función asignada (incluye M.funcion = function())
    if not func_name then
      func_name, params = line:match(M.patterns.module_function)
      if func_name then
        func_type = "assigned_function"
      end
    end

    -- Si se encontró una función, procesarla
    if func_name then
      log.debug("Función detectada en posición del cursor: " .. func_name)

      -- Encontrar el final de la función
      local end_line = M.find_end_line(lines, func_line, func_type)
      if not end_line then
        -- Si no se puede determinar el final, buscar la línea "end" más cercana
        for j = func_line + 1, math.min(func_line + 100, #lines) do
          if lines[j]:match("^%s*end%s*$") or lines[j]:match("^%s*end[%s,%)%]}]") then
            end_line = j
            break
          end
        end

        -- Si aún no se encuentra, usar una estimación
        if not end_line then
          end_line = func_line + 5 -- Asumimos que la función tiene al menos 5 líneas
        end
      end

      -- Verificar si tiene documentación
      local doc_info = M.find_doc_block(lines, func_line)
      local has_doc = doc_info ~= nil

      -- Extraer parámetros, limpiando espacios y valores por defecto
      local param_names = {}
      if params then
        for param in params:gmatch("([^,]+)") do
          -- Eliminar espacios y valores por defecto
          param = param:match("^%s*([^=]+)") or param
          param = param:match("^%s*(.-)%s*$") -- Eliminar espacios
          if param and param ~= "" then
            table.insert(param_names, param)
          end
        end
      end

      -- Contenido de la función
      local content_lines = {}
      for j = func_line, end_line do
        table.insert(content_lines, lines[j])
      end
      local content = table.concat(content_lines, "\n")

      -- Determinar tipo de problema
      local issue_type = nil
      if not has_doc then
        issue_type = issue_types.MISSING
      else
        -- Verificar si la documentación está desactualizada o incompleta
        local is_outdated = M.is_documentation_outdated(buffer, doc_info.lines, content_lines)
        if is_outdated then
          issue_type = issue_types.OUTDATED
        else
          local is_incomplete = M.is_documentation_incomplete(buffer, doc_info.lines, param_names)
          if is_incomplete then
            issue_type = issue_types.INCOMPLETE
          end
        end
      end

      -- Crear item de documentación
      return {
        name = func_name,
        type = func_type,
        bufnr = buffer,
        start_line = func_line,
        end_line = end_line,
        content = content,
        has_doc = has_doc,
        issue_type = issue_type or issue_types.MISSING, -- Por defecto, asumimos que falta documentación
        doc_start_line = has_doc and doc_info.start_line or nil,
        doc_end_line = has_doc and doc_info.end_line or nil,
        doc_lines = has_doc and doc_info.lines or nil,
        params = param_names
      }
    end
  end

  -- Si no encontramos ninguna función, buscar entre todas las funciones detectadas en un escaneo completo
  log.debug("Realizando escaneo completo para encontrar función en la posición " .. row)
  local items = M.scan_buffer(buffer)
  for _, item in ipairs(items) do
    if row >= item.start_line and row <= item.end_line then
      return item
    end
  end

  return nil
end

-- Determina si la documentación de una función está desactualizada para Lua
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param func_lines tabla: Líneas de la función
-- @return boolean: true si está desactualizada, false en caso contrario
function M.is_documentation_outdated(buffer, doc_lines, func_lines)
  if not doc_lines or not func_lines then
    return false
  end

  local doc_text = table.concat(doc_lines, "\n")
  local func_text = table.concat(func_lines, "\n")

  -- Extraer parámetros de la función
  local func_first_line = func_lines[1] or ""
  local func_params = ""

  -- Extraer parámetros según el tipo de definición
  local _, params = func_first_line:match(M.patterns.function_start)
  if not params then
    local _, _, method_params = func_first_line:match(M.patterns.method_start)
    if method_params then params = method_params end
  end
  if not params then
    local _, local_params = func_first_line:match(M.patterns.local_function)
    if local_params then params = local_params end
  end
  if not params then
    local _, module_params = func_first_line:match(M.patterns.module_function)
    if module_params then params = module_params end
  end

  -- Si no encontramos parámetros, no hay problema
  if not params then
    return false
  end

  -- Verificar que todos los parámetros estén documentados
  local param_list = {}
  for param in params:gmatch("([^,]+)") do
    param = param:match("^%s*(.-)%s*$") -- Eliminar espacios
    if param ~= "" then
      table.insert(param_list, param)
    end
  end

  -- Verificar que cada parámetro esté en la documentación
  for _, param in ipairs(param_list) do
    -- En Lua, el patrón de documentación común es "-- @param nombre tipo: descripción"
    local param_pattern = "%-%-%s*@param%s+" .. param .. "[%s:]"
    if not doc_text:match(param_pattern) then
      return true -- Hay un parámetro no documentado
    end
  end

  return false
end

-- Determina si la documentación de una función está incompleta para Lua
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param param_names tabla: Nombres de los parámetros
-- @return boolean: true si está incompleta, false en caso contrario
function M.is_documentation_incomplete(buffer, doc_lines, param_names)
  if not doc_lines or not param_names then
    return false
  end

  local doc_text = table.concat(doc_lines, "\n")

  -- Verificar presencia de @param para cada parámetro
  for _, param in ipairs(param_names) do
    if param ~= "" and param ~= "..." then
      local param_pattern = "%-%-%s*@param%s+" .. param .. "[%s:]"
      if not doc_text:match(param_pattern) then
        return true -- Documentación incompleta
      end
    end
  end

  -- Verificar si hay un valor de retorno pero falta @return
  if doc_text:match("return%s+[^%s]") and not doc_text:match("%-%-%s*@return") then
    return true
  end

  return false
end

-- Normaliza la documentación para Lua
-- @param doc_block string: Bloque de documentación
-- @return string: Documentación normalizada
function M.normalize_documentation(doc_block)
  if not doc_block or doc_block == "" then
    return ""
  end

  -- Eliminar líneas vacías al inicio y al final
  doc_block = doc_block:gsub("^%s*(.-)%s*$", "%1")

  -- Asegurar que la documentación tenga el formato correcto para Lua
  local lines = vim.split(doc_block, "\n")
  local normalized_lines = {}

  for _, line in ipairs(lines) do
    -- Asegurar que cada línea comience con --
    if not line:match("^%s*%-%-") and line:match("%S") then
      line = "-- " .. line
    end
    table.insert(normalized_lines, line)
  end

  return table.concat(normalized_lines, "\n")
end

-- Aplica documentación a una función en Lua
-- @param buffer número: ID del buffer
-- @param start_line número: Línea antes de la cual insertar la documentación
-- @param doc_block string: Bloque de documentación a insertar
-- @return boolean: true si se aplicó correctamente, false en caso contrario
function M.apply_documentation(buffer, start_line, doc_block, item)
  if not doc_block or doc_block == "" then
    log.error("Bloque de documentación vacío")
    return false
  end

  -- Asegurar que la documentación esté en formato Lua
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

  -- Obtener la línea de destino para la indentación y verificar que sea código válido
  local target_line = ""
  if start_line <= buffer_line_count then
    local lines = vim.api.nvim_buf_get_lines(buffer, start_line - 1, start_line, false)
    target_line = lines[1] or ""

    -- Verificar que la línea de destino contiene código real (no solo comentarios o espacios)
    if target_line:match("^%s*$") or target_line:match("^%s*%-%-") then
      log.warn("La línea de destino parece vacía o un comentario. Verificando contexto...")

      -- Verificar las siguientes líneas para asegurarse de que estamos antes de código real
      local found_code = false
      for i = start_line, math.min(start_line + 5, buffer_line_count) do
        local check_line = vim.api.nvim_buf_get_lines(buffer, i - 1, i, false)[1] or ""
        if check_line:match("%S") and not check_line:match("^%s*%-%-") then
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

  for i = 1, #lines do
    local line = lines[i]

    -- Buscar definiciones de funciones en Lua
    local is_function = line:match(M.patterns.function_start) ~= nil or
                        line:match(M.patterns.local_function) ~= nil or
                        line:match(M.patterns.module_function) ~= nil or
                        line:match(M.patterns.method_start) ~= nil

    if is_function then
      local doc_info = M.find_doc_block(lines, i)
      -- Si tiene documentación y es suficientemente extensa (al menos 3 líneas)
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

  -- Verificaciones de seguridad
  if not vim.api.nvim_buf_is_valid(buffer) then
    log.error("Buffer inválido al actualizar documentación")
    return false
  end

  local buffer_line_count = vim.api.nvim_buf_line_count(buffer)

  -- Verificar que las líneas están dentro del rango del buffer
  if doc_start_line <= 0 or doc_start_line > buffer_line_count then
    log.error("Línea de inicio de documentación fuera de rango: " .. doc_start_line .. " (total líneas: " .. buffer_line_count .. ")")
    return false
  end

  if doc_end_line <= 0 or doc_end_line > buffer_line_count then
    log.error("Línea de fin de documentación fuera de rango: " .. doc_end_line .. " (total líneas: " .. buffer_line_count .. ")")
    return false
  end

  -- Verificar que doc_start_line <= doc_end_line
  if doc_start_line > doc_end_line then
    log.error("Línea de inicio (" .. doc_start_line .. ") posterior a línea de fin (" .. doc_end_line .. ")")
    return false
  end

  -- Guardar la línea siguiente a la documentación para verificar después
  local next_line_idx = doc_end_line
  local next_line = ""
  if next_line_idx <= buffer_line_count then
    next_line = vim.api.nvim_buf_get_lines(buffer, next_line_idx - 1, next_line_idx, false)[1] or ""
  end

  -- Verificar si la línea siguiente contiene código importante
  local contains_important_code = next_line:match("%S") and not next_line:match("^%s*%-%-")
  local contains_function_def = next_line:match("function") or next_line:match("local%s+function") or
                              next_line:match("=%s*function")

  -- Capturar un contexto más amplio
  local context_start = math.max(1, doc_start_line - 5)
  local context_end = math.min(buffer_line_count, doc_end_line + 10)
  local context_lines = vim.api.nvim_buf_get_lines(buffer, context_start - 1, context_end, false)

  -- Asegurar que la documentación esté en formato Lua
  doc_block = M.normalize_documentation(doc_block)

  -- Convertir a líneas
  local doc_lines = vim.split(doc_block, "\n")

  -- Obtener la indentación de la primera línea de la documentación existente
  local first_doc_line = vim.api.nvim_buf_get_lines(buffer, doc_start_line - 1, doc_start_line, false)[1] or ""
  local indent = first_doc_line:match("^(%s*)")

  -- Aplicar indentación a las líneas de documentación
  for i, line in ipairs(doc_lines) do
    if line ~= "" then
      doc_lines[i] = indent .. line
    end
  end

  log.debug("Actualizando documentación desde línea " .. doc_start_line .. " hasta " .. doc_end_line)

  -- Hacer una copia de seguridad de las líneas que se van a reemplazar y su entorno
  local backup_lines = vim.api.nvim_buf_get_lines(buffer, doc_start_line - 1, doc_end_line, false)

  -- Número de líneas en el bloque original de documentación
  local original_doc_lines_count = doc_end_line - doc_start_line + 1

  -- Comparar longitudes para anticipar problemas
  if math.abs(#doc_lines - original_doc_lines_count) > 10 then
    log.warn("La diferencia de tamaño entre documentación original y nueva es significativa: " ..
             original_doc_lines_count .. " vs " .. #doc_lines)

    -- Si la nueva documentación es mucho más corta, puede ser problemático
    if #doc_lines < original_doc_lines_count / 2 and original_doc_lines_count > 5 then
      log.warn("La nueva documentación es mucho más corta que la original. Verificando contenido...")
      -- Aquí podríamos implementar verificaciones adicionales de contenido
    end
  end

  -- Añadir línea en blanco al final si la documentación actual no termina con una
  if #doc_lines > 0 and doc_lines[#doc_lines] ~= "" and next_line ~= "" then
    table.insert(doc_lines, "")
  end

  -- Reemplazar la documentación existente
  vim.api.nvim_buf_set_lines(buffer, doc_start_line - 1, doc_end_line, false, doc_lines)

  -- Verificar que la siguiente línea sigue siendo la misma (no se borró código)
  if next_line_idx <= buffer_line_count then
    -- Calcular el nuevo índice de la línea siguiente
    local new_next_line_idx = doc_start_line + #doc_lines - 1
    local current_next_line = ""
    if new_next_line_idx < vim.api.nvim_buf_line_count(buffer) then
      current_next_line = vim.api.nvim_buf_get_lines(buffer, new_next_line_idx, new_next_line_idx + 1, false)[1] or ""
    end

    -- Si la línea siguiente cambió y contenía código, esto podría ser un problema
    if current_next_line ~= next_line and contains_important_code then
      log.error("¡Advertencia! La línea siguiente a la documentación ha cambiado. Posible pérdida de código.")
      log.error("Original: '" .. next_line .. "'")
      log.error("Nueva: '" .. current_next_line .. "'")

      -- Si parece que se eliminó código importante, restaurar el estado original
      if (next_line:match("[%w_]") and not current_next_line:match("[%w_]")) or contains_function_def then
        log.warn("Detectada posible pérdida de código importante. Restaurando documentación original...")
        vim.api.nvim_buf_set_lines(buffer, doc_start_line - 1, doc_start_line - 1 + #doc_lines, false, backup_lines)
        vim.notify("Se detectó un problema al actualizar la documentación. Se ha restaurado la documentación original para evitar pérdida de código.", vim.log.levels.WARN)
        return false
      end
    end
  end

  -- Verificar la integridad del código después de la actualización
  local post_update_lines = vim.api.nvim_buf_get_lines(buffer, context_start - 1, context_end, false)
  local function_line_missing = false

  -- Verificar si alguna línea con definición de función ha desaparecido
  for i, line in ipairs(context_lines) do
    local is_function = line:match("function") or line:match("local%s+function") or line:match("=%s*function")
    if is_function then
      local found = false
      for j, post_line in ipairs(post_update_lines) do
        if post_line == line then
          found = true
          break
        end
      end

      if not found then
        function_line_missing = true
        log.error("¡Detectada pérdida de línea de definición de función! Línea: '" .. line .. "'")
        break
      end
    end
  end

  -- Restaurar si se detecta pérdida de función
  if function_line_missing then
    log.warn("Detectada pérdida de definición de función. Restaurando estado original...")
    vim.api.nvim_buf_set_lines(buffer, doc_start_line - 1, doc_start_line - 1 + #doc_lines, false, backup_lines)
    vim.notify("Se detectó pérdida de código de función al actualizar la documentación. Se ha restaurado la documentación original.", vim.log.levels.ERROR)
    return false
  end

  return true
end

return M