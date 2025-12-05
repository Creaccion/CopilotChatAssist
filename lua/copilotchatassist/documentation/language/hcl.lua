-- Manejador específico para documentación de HCL/Terraform
-- Extiende el manejador común con funcionalidades específicas para HCL/Terraform

local M = {}
local common = require("copilotchatassist.documentation.language.common")
local log = require("copilotchatassist.utils.log")

-- Heredar funcionalidad básica del manejador común
for k, v in pairs(common) do
  M[k] = v
end

-- Sobreescribir patrones para adaptarlos a HCL/Terraform
M.patterns = {
  -- Patrones específicos para HCL/Terraform
  resource_start = "^%s*resource%s+[\"']([%w_.-]+)[\"']%s+[\"']([%w_.-]+)[\"']%s*{",
  data_start = "^%s*data%s+[\"']([%w_.-]+)[\"']%s+[\"']([%w_.-]+)[\"']%s*{",
  module_start = "^%s*module%s+[\"']([%w_.-]+)[\"']%s*{",
  variable_start = "^%s*variable%s+[\"']([%w_.-]+)[\"']%s*{",
  output_start = "^%s*output%s+[\"']([%w_.-]+)[\"']%s*{",
  locals_start = "^%s*locals%s*{",
  provider_start = "^%s*provider%s+[\"']([%w_.-]+)[\"']%s*{",
  block_start = "^%s*([%w_.-]+)%s+[\"']?([%w_.-]+)[\"']?%s*{",
  comment_start = "^%s*#%s*",
  comment_line = "^%s*#%s?(.*)",
  multi_comment_start = "^%s*/%*",
  multi_comment_end = "%*/",
  block_end = "^%s*}",
}

-- Encuentra la línea de finalización de un bloque en HCL
-- @param lines tabla: Líneas del buffer
-- @param start_line número: Línea de inicio
-- @param item_type string: Tipo de elemento ("resource", "data", etc)
-- @return número: Número de línea final o nil si no se puede determinar
function M.find_end_line(lines, start_line, item_type)
  if not lines or not start_line or start_line > #lines then
    return nil
  end

  local depth = 0
  local found_opening_bracket = false

  -- En HCL, buscamos la llave de cierre correspondiente al mismo nivel
  for i = start_line, #lines do
    local line = lines[i]

    -- Saltamos comentarios
    if line:match("^%s*#") or line:match("^%s*/%*") or line:match("%*/") then
      goto continue
    end

    -- Contar las llaves para mantener el seguimiento del nivel de anidamiento
    for j = 1, #line do
      local char = line:sub(j, j)

      -- Ignoramos caracteres en comentarios
      if line:sub(j):match("^#") then
        break  -- Ignorar resto de la línea
      end

      if char == "{" then
        depth = depth + 1
        found_opening_bracket = true
      elseif char == "}" then
        depth = depth - 1
        -- Si hemos cerrado todas las llaves y hemos encontrado una apertura antes
        if depth == 0 and found_opening_bracket then
          return i
        end
      end
    end

    ::continue::
  end

  return #lines  -- Si no se puede determinar, devolver la última línea
end

-- Busca documentación en líneas de texto para HCL/Terraform
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

  -- Buscar comentarios justo antes del bloque
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

    -- Detectar fin de bloque de comentarios multi-línea (principio al buscar hacia atrás)
    if line:match("%*/") then
      in_comment_block = true
      table.insert(doc_lines, 1, line)
      if not doc_start then
        doc_start = i
      end
      goto continue
    end

    -- Detectar inicio de bloque de comentarios multi-línea (fin al buscar hacia atrás)
    if line:match("^%s*/%*") then
      in_comment_block = false
      table.insert(doc_lines, 1, line)
      if not doc_start then
        doc_start = i
      end
      break
    end

    -- Dentro de un bloque de comentarios multi-línea
    if in_comment_block then
      table.insert(doc_lines, 1, line)
      if not doc_start then
        doc_start = i
      end
      goto continue
    end

    -- Detectar comentarios de línea
    local is_comment_line = line:match("^%s*#")
    if is_comment_line then
      table.insert(doc_lines, 1, line)
      if not doc_start then
        doc_start = i
      end
    else
      -- Si encontramos una línea que no es comentario, terminamos
      if doc_start then
        break
      else
        break  -- No hay documentación
      end
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

-- Escanea un buffer en busca de problemas de documentación en HCL/Terraform
-- @param buffer número: ID del buffer a escanear
-- @return tabla: Lista de elementos con problemas de documentación
function M.scan_buffer(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local items = {}
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  -- Buscar definiciones de recursos, datos, módulos, etc. en HCL
  for i, line in ipairs(lines) do
    -- Omitir líneas de comentario en esta fase
    if line:match("^%s*#") or line:match("^%s*/%*") then
      goto continue
    end

    -- Variables para almacenar información del elemento
    local item_name = nil
    local item_type = nil
    local item_subtype = nil

    -- Resources
    local resource_type, resource_name = line:match(M.patterns.resource_start)
    if resource_type and resource_name then
      item_name = resource_type .. "." .. resource_name
      item_type = "resource"
      item_subtype = resource_type
    end

    -- Data sources
    if not item_name then
      local data_type, data_name = line:match(M.patterns.data_start)
      if data_type and data_name then
        item_name = data_type .. "." .. data_name
        item_type = "data"
        item_subtype = data_type
      end
    end

    -- Modules
    if not item_name then
      local module_name = line:match(M.patterns.module_start)
      if module_name then
        item_name = module_name
        item_type = "module"
      end
    end

    -- Variables
    if not item_name then
      local variable_name = line:match(M.patterns.variable_start)
      if variable_name then
        item_name = variable_name
        item_type = "variable"
      end
    end

    -- Outputs
    if not item_name then
      local output_name = line:match(M.patterns.output_start)
      if output_name then
        item_name = output_name
        item_type = "output"
      end
    end

    -- Locals
    if not item_name and line:match(M.patterns.locals_start) then
      item_name = "locals"
      item_type = "locals"
    end

    -- Providers
    if not item_name then
      local provider_name = line:match(M.patterns.provider_start)
      if provider_name then
        item_name = provider_name
        item_type = "provider"
      end
    end

    -- Otros bloques genéricos
    if not item_name then
      local block_type, block_name = line:match(M.patterns.block_start)
      if block_type and not block_type:match("^%s*resource") and not block_type:match("^%s*data") then
        item_name = block_name and (block_type .. "." .. block_name) or block_type
        item_type = "block"
        item_subtype = block_type
      end
    end

    -- Si se encontró un elemento documentable, procesarlo
    if item_name then
      log.debug("Elemento detectado: " .. item_name .. " (" .. item_type .. ") en línea " .. i)

      -- Encontrar el final del elemento
      local end_line = M.find_end_line(lines, i, item_type)
      if not end_line then
        -- Si no se puede determinar el final, usar una estimación
        end_line = math.min(i + 30, #lines)  -- Los bloques HCL pueden ser grandes
      end

      -- Verificar si tiene documentación
      local doc_info = M.find_doc_block(lines, i)
      local has_doc = doc_info ~= nil

      -- Contenido del elemento
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
        -- HCL/Terraform no tiene un formato estricto para la documentación,
        -- así que por ahora consideramos completa cualquier documentación existente
        issue_type = nil
      end

      -- Si hay un problema, agregar a la lista
      if issue_type then
        table.insert(items, {
          name = item_name,
          type = item_type,
          subtype = item_subtype,
          bufnr = buffer,
          start_line = i,
          end_line = end_line,
          content = content,
          has_doc = has_doc,
          issue_type = issue_type,
          doc_start_line = has_doc and doc_info.start_line or nil,
          doc_end_line = has_doc and doc_info.end_line or nil,
          doc_lines = has_doc and doc_info.lines or nil,
          params = {}  -- HCL no tiene parámetros formales
        })
      end
    end

    ::continue::
  end

  log.debug("Se encontraron " .. #items .. " elementos con problemas de documentación en el archivo HCL/Terraform")
  return items
end

-- Determina si la documentación de una función está desactualizada
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param element_lines tabla: Líneas del elemento
-- @return boolean: true si está desactualizada, false en caso contrario
function M.is_documentation_outdated(buffer, doc_lines, element_lines)
  -- Para HCL/Terraform, no implementamos verificación detallada de actualización
  -- Simplemente asumimos que está actualizada si existe
  return false
end

-- Determina si la documentación de una función está incompleta
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param param_names tabla: Nombres de los parámetros
-- @return boolean: true si está incompleta, false en caso contrario
function M.is_documentation_incomplete(buffer, doc_lines, param_names)
  -- Para HCL/Terraform, no implementamos verificación detallada de completitud
  -- Simplemente asumimos que está completa si existe
  return false
end

-- Normaliza la documentación para HCL/Terraform
-- @param doc_block string: Bloque de documentación
-- @return string: Documentación normalizada
function M.normalize_documentation(doc_block)
  if not doc_block or doc_block == "" then
    return ""
  end

  -- Eliminar líneas vacías al inicio y al final
  doc_block = doc_block:gsub("^%s*(.-)%s*$", "%1")

  -- Asegurar que la documentación tenga el formato correcto para HCL/Terraform
  local lines = vim.split(doc_block, "\n")
  local normalized_lines = {}

  -- Determinar si ya es un bloque de comentarios
  local is_comment_block = false
  local is_multi_line_comment = false

  for _, line in ipairs(lines) do
    if line:match("^%s*#") then
      is_comment_block = true
    end
    if line:match("^%s*/%*") or line:match("%*/") then
      is_multi_line_comment = true
      break
    end
  end

  -- Si ya tiene formato de comentarios HCL, usarlo como está
  if is_comment_block or is_multi_line_comment then
    return doc_block
  end

  -- Si no es un comentario, convertir a comentarios de línea (# ...)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      table.insert(normalized_lines, "# " .. line)
    else
      table.insert(normalized_lines, "#")
    end
  end

  return table.concat(normalized_lines, "\n")
end

-- Aplica documentación a un elemento en HCL/Terraform
-- @param buffer número: ID del buffer
-- @param start_line número: Línea antes de la cual insertar la documentación
-- @param doc_block string: Bloque de documentación a insertar
-- @return boolean: true si se aplicó correctamente, false en caso contrario
function M.apply_documentation(buffer, start_line, doc_block, item)
  if not doc_block or doc_block == "" then
    log.error("Bloque de documentación vacío")
    return false
  end

  -- Asegurar que la documentación esté en formato HCL/Terraform
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
    if target_line:match("^%s*$") or target_line:match("^%s*#") or target_line:match("^%s*/%*") then
      log.warn("La línea de destino parece vacía o un comentario. Verificando contexto...")

      -- Verificar las siguientes líneas para asegurarse de que estamos antes de código real
      local found_code = false
      for i = start_line, math.min(start_line + 5, buffer_line_count) do
        local check_line = vim.api.nvim_buf_get_lines(buffer, i - 1, i, false)[1] or ""
        if check_line:match("%S") and not check_line:match("^%s*#") and not check_line:match("^%s*/%*") then
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

  -- Buscar bloques consecutivos de comentarios antes de recursos o bloques
  for i = 1, #lines - 1 do
    local line = lines[i]
    local next_line = lines[i + 1]

    -- Si encontramos un comentario seguido de un recurso, módulo, etc.
    if line:match("^%s*#") and
       (next_line:match("^%s*resource") or
        next_line:match("^%s*data") or
        next_line:match("^%s*module") or
        next_line:match("^%s*variable") or
        next_line:match("^%s*output")) then

      -- Buscar hacia atrás para encontrar el comienzo del bloque de comentarios
      local doc_start = i
      while doc_start > 1 and lines[doc_start - 1]:match("^%s*#") do
        doc_start = doc_start - 1
      end

      -- Recoger todas las líneas de comentarios consecutivas
      local doc_lines = {}
      for j = doc_start, i do
        table.insert(doc_lines, lines[j])
      end

      local doc_text = table.concat(doc_lines, "\n")
      if #doc_text > 30 then  -- Asegurarse de que sea un comentario significativo
        table.insert(examples, doc_text)

        if #examples >= max_examples then
          break
        end
      end
    end

    -- También buscar bloques de comentarios multi-línea
    if line:match("^%s*/%*") then
      local doc_start = i
      local doc_end = nil

      -- Buscar el fin del bloque
      for j = i + 1, math.min(i + 20, #lines) do
        if lines[j]:match("%*/") then
          doc_end = j
          break
        end
      end

      if doc_end then
        local doc_lines = {}
        for j = doc_start, doc_end do
          table.insert(doc_lines, lines[j])
        end

        local doc_text = table.concat(doc_lines, "\n")
        table.insert(examples, doc_text)

        if #examples >= max_examples then
          break
        end

        i = doc_end  -- Saltar al final del bloque
      end
    end
  end

  return examples
end

-- Crear un alias para terraform
M.terraform = M

return M