-- Manejador específico para documentación de Ruby
-- Extiende el manejador común con funcionalidades específicas para Ruby

local M = {}
local common = require("copilotchatassist.documentation.language.common")
local log = require("copilotchatassist.utils.log")

-- Heredar funcionalidad básica del manejador común
for k, v in pairs(common) do
  M[k] = v
end

-- Sobreescribir patrones para adaptarlos a Ruby
M.patterns = {
  -- Patrones específicos para Ruby
  class_start = "^%s*class%s+([%w_:]+)%s*(<?)%s*([%w_:]*)",
  module_start = "^%s*module%s+([%w_:]+)",
  method_start = "^%s*def%s+([%w_?!]+)%s*(?:%s*(.*)%s*)?",
  singleton_method_start = "^%s*def%s+self%.([%w_?!]+)%s*(?:%s*(.*)%s*)?",
  class_method_start = "^%s*def%s+self%.([%w_?!]+)%s*(?:%s*(.*)%s*)?",
  attr_accessors = "^%s*attr_accessor%s+:([%w_,]+)",
  attr_readers = "^%s*attr_reader%s+:([%w_,]+)",
  attr_writers = "^%s*attr_writer%s+:([%w_,]+)",
  comment_start = "^%s*#%s*",
  block_comment_start = "^%s*=begin",
  block_comment_end = "^%s*=end",
  yard_tag = "^%s*#%s*@([%w_]+)",
  rdoc_tag = "^%s*#%s*:([%w_]+):",
}

-- Encuentra la línea de finalización de un método, clase o módulo en Ruby
-- @param lines tabla: Líneas del buffer
-- @param start_line número: Línea de inicio
-- @param item_type string: Tipo de elemento ("method", "class", "module")
-- @return número: Número de línea final o nil si no se puede determinar
function M.find_end_line(lines, start_line, item_type)
  if not lines or not start_line or start_line > #lines then
    return nil
  end

  local end_pattern
  if item_type == "method" then
    end_pattern = "^%s*end"
  else  -- class, module
    end_pattern = "^%s*end"
  end

  local indent_level
  local start_line_content = lines[start_line]
  indent_level = #(start_line_content:match("^(%s*)") or "")

  -- En Ruby, buscamos la palabra clave "end" con la misma o menor indentación
  for i = start_line + 1, #lines do
    local line = lines[i]

    -- Ignoramos líneas de comentarios
    if line:match("^%s*#") then
      goto continue
    end

    -- Si encontramos un "end" con la misma o menor indentación, es nuestro fin
    if line:match(end_pattern) then
      local this_indent = #(line:match("^(%s*)") or "")
      if this_indent <= indent_level then
        return i
      end
    end

    ::continue::
  end

  return #lines  -- Si no se puede determinar, devolver la última línea
end

-- Busca documentación en líneas de texto para Ruby
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

  -- Buscar comentarios justo antes de la definición
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

    -- Detectar comentarios Ruby (línea o bloque)
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

-- Escanea un buffer en busca de problemas de documentación en Ruby
-- @param buffer número: ID del buffer a escanear
-- @return tabla: Lista de elementos con problemas de documentación
function M.scan_buffer(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local items = {}
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  -- Buscar definiciones de clases, módulos y métodos en Ruby
  for i, line in ipairs(lines) do
    -- Omitir líneas de comentario en esta fase
    if line:match("^%s*#") or line:match("^%s*=begin") or line:match("^%s*=end") then
      goto continue
    end

    -- Variables para almacenar la información del elemento
    local item_name = nil
    local item_type = nil
    local params = nil

    -- Clases
    local class_name, inherits, parent_class = line:match(M.patterns.class_start)
    if class_name then
      item_name = class_name
      item_type = "class"
    end

    -- Módulos
    if not item_name then
      local module_name = line:match(M.patterns.module_start)
      if module_name then
        item_name = module_name
        item_type = "module"
      end
    end

    -- Métodos de instancia
    if not item_name then
      local method_name, method_params = line:match(M.patterns.method_start)
      if method_name then
        item_name = method_name
        item_type = "method"
        params = method_params
      end
    end

    -- Métodos de clase (def self.method)
    if not item_name then
      local class_method_name, class_method_params = line:match(M.patterns.class_method_start)
      if class_method_name then
        item_name = "self." .. class_method_name
        item_type = "class_method"
        params = class_method_params
      end
    end

    -- Si se encontró un elemento documentable, procesarlo
    if item_name then
      log.debug("Elemento detectado: " .. item_name .. " (" .. item_type .. ") en línea " .. i)

      -- Encontrar el final del elemento
      local end_line = M.find_end_line(lines, i, item_type)
      if not end_line then
        -- Si no se puede determinar el final, usar una estimación
        end_line = i + 10  -- Asumimos que el elemento tiene al menos 10 líneas
      end

      -- Verificar si tiene documentación
      local doc_info = M.find_doc_block(lines, i)
      local has_doc = doc_info ~= nil

      -- Extraer parámetros para métodos
      local param_names = {}
      if params and (item_type == "method" or item_type == "class_method") then
        -- Limpiar parámetros y extraer nombres
        params = params:gsub("%(", ""):gsub("%)", "")
        for param in params:gmatch("([^,]+)") do
          -- Manejar parámetros con valores por defecto
          local param_name = param:match("^%s*([%w_]+)[=%s]") or param:match("^%s*([%w_]+)%s*$")
          -- Manejar parámetros keyword
          if not param_name then
            param_name = param:match("^%s*:([%w_]+)")
          end
          if param_name then
            table.insert(param_names, param_name)
          end
        end
      end

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
      elseif has_doc then
        -- Verificar si la documentación está incompleta
        local is_incomplete = M.is_documentation_incomplete(buffer, doc_info.lines, param_names)
        if is_incomplete then
          issue_type = issue_types.INCOMPLETE
        else
          local is_outdated = M.is_documentation_outdated(buffer, doc_info.lines, content_lines)
          if is_outdated then
            issue_type = issue_types.OUTDATED
          end
        end
      end

      -- Si hay un problema, agregar a la lista
      if issue_type then
        table.insert(items, {
          name = item_name,
          type = item_type,
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

  log.debug("Se encontraron " .. #items .. " elementos con problemas de documentación en el archivo Ruby")
  return items
end

-- Determina si la documentación de un elemento está incompleta en Ruby
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param param_names tabla: Nombres de los parámetros
-- @return boolean: true si está incompleta, false en caso contrario
function M.is_documentation_incomplete(buffer, doc_lines, param_names)
  if not doc_lines or not param_names or #param_names == 0 then
    return false
  end

  local doc_text = table.concat(doc_lines, "\n")

  -- Verificar formatos de documentación para parámetros (YARD o RDoc)
  local uses_yard = doc_text:match("@param")
  local uses_rdoc = doc_text:match("==+ Parameters") or doc_text:match(":param:")

  -- Si no usa ningún formato de documentación reconocible, no podemos determinar incompletitud
  if not uses_yard and not uses_rdoc then
    return false
  end

  -- Verificar parámetros según el formato
  for _, param in ipairs(param_names) do
    if param ~= "" then
      local param_documented = false

      if uses_yard then
        param_documented = doc_text:match("@param%s+" .. param .. "[ :]") ~= nil
      end

      if uses_rdoc and not param_documented then
        param_documented = doc_text:match(":param:%s+" .. param .. "[ :]") ~= nil or
                           doc_text:match("\\*%s*" .. param .. "\\*%s*[-:]") ~= nil
      end

      if not param_documented then
        return true  -- Falta documentación de algún parámetro
      end
    end
  end

  -- Verificar si falta documentación de retorno para métodos
  if doc_text:match("return[%s%w_.;]+") and not doc_text:match("@return") and not doc_text:match("==+ Return") and not doc_text:match(":returns?:") then
    return true
  end

  return false
end

-- Determina si la documentación de un elemento está desactualizada en Ruby
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param element_lines tabla: Líneas del elemento
-- @return boolean: true si está desactualizada, false en caso contrario
function M.is_documentation_outdated(buffer, doc_lines, element_lines)
  -- Implementación básica: verificar si hay documentación de parámetros que ya no existen
  if not doc_lines or not element_lines then
    return false
  end

  local doc_text = table.concat(doc_lines, "\n")
  local element_text = table.concat(element_lines, "\n")

  -- Extraer parámetros documentados (YARD)
  local documented_params = {}
  for param in doc_text:gmatch("@param%s+([%w_]+)") do
    documented_params[param] = true
  end

  -- Extraer parámetros documentados (RDoc)
  for param in doc_text:gmatch(":param:%s+([%w_]+)") do
    documented_params[param] = true
  end

  -- Extraer parámetros reales del método
  local actual_params = {}
  local method_line = element_lines[1] or ""
  local param_str = method_line:match("def%s+[%w_.]+%s*%((.-)%)") or
                    method_line:match("def%s+[%w_.]+%s+(.+)$")

  if param_str then
    for param in param_str:gmatch("([^,]+)") do
      local param_name = param:match("^%s*([%w_]+)[=%s]") or param:match("^%s*([%w_]+)%s*$")
      if not param_name then
        param_name = param:match("^%s*:([%w_]+)")
      end
      if param_name then
        actual_params[param_name] = true
      end
    end
  end

  -- Verificar si hay parámetros documentados que ya no existen
  for param_name in pairs(documented_params) do
    if not actual_params[param_name] then
      return true  -- Hay parámetros documentados que ya no están en el método
    end
  end

  return false
end

-- Normaliza la documentación para Ruby
-- @param doc_block string: Bloque de documentación
-- @return string: Documentación normalizada
function M.normalize_documentation(doc_block)
  if not doc_block or doc_block == "" then
    return ""
  end

  -- Eliminar líneas vacías al inicio y al final
  doc_block = doc_block:gsub("^%s*(.-)%s*$", "%1")

  -- Asegurar que la documentación tenga el formato correcto para Ruby
  local lines = vim.split(doc_block, "\n")
  local normalized_lines = {}

  -- Determinar si usa YARD, RDoc o comentarios simples
  local uses_yard = false
  local uses_rdoc = false
  for _, line in ipairs(lines) do
    if line:match("@[%w_]+") then
      uses_yard = true
      break
    elseif line:match("^=") or line:match(":param:") or line:match(":return:") then
      uses_rdoc = true
      break
    end
  end

  -- Si no usa ningún formato específico, convertir a YARD
  if not uses_yard and not uses_rdoc then
    uses_yard = true
  end

  -- Normalizar según el formato
  for _, line in ipairs(lines) do
    -- Limpiar prefijos existentes
    local content = line:gsub("^%s*#%s*", "")

    -- Asegurar que cada línea comience con # (comentario Ruby)
    if uses_yard or not uses_rdoc then
      if line:match("%S") and not line:match("^%s*#") then
        line = "# " .. content
      else
        line = "# " .. content
      end
      table.insert(normalized_lines, line)
    else
      -- Para RDoc mantener formato original pero asegurar comentarios
      if not line:match("^%s*#") and line:match("%S") then
        line = "# " .. line
      end
      table.insert(normalized_lines, line)
    end
  end

  return table.concat(normalized_lines, "\n")
end

-- Aplica documentación a un elemento en Ruby
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

  -- Asegurar que la documentación esté en formato Ruby
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

  -- Verificar si ya existe documentación similar para evitar duplicados
  local all_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local doc_content = table.concat(doc_lines, "\n")
  local duplicates = {}

  -- Buscar bloques de documentación existentes
  local i = 1
  while i < #all_lines do
    local line = all_lines[i]

    -- Detectar inicio de bloques de comentarios
    if line:match("^%s*#") or line:match("^%s*=begin") then
      local comment_start = i
      local comment_end = i
      local is_block_comment = line:match("^%s*=begin") ~= nil
      local comment_lines = {line}

      -- Buscar el fin del bloque de comentarios
      for j = i + 1, math.min(i + 30, #all_lines) do
        if is_block_comment then
          table.insert(comment_lines, all_lines[j])
          comment_end = j
          if all_lines[j]:match("^%s*=end") then
            break
          end
        elseif all_lines[j]:match("^%s*#") then
          table.insert(comment_lines, all_lines[j])
          comment_end = j
        else
          break
        end
      end

      -- Si el bloque es lo suficientemente grande, considerarlo como posible duplicado
      if #comment_lines >= 3 then
        local comment_content = table.concat(comment_lines, "\n")

        -- Función para calcular la similitud entre dos cadenas
        local function similarity_score(str1, str2)
          -- Eliminar espacios en blanco y caracteres especiales para comparación
          str1 = str1:gsub("%s+", "")
          str2 = str2:gsub("%s+", "")

          -- Si una cadena es significativamente más larga que la otra, probablemente no son similares
          if #str1 > #str2 * 2 or #str2 > #str1 * 2 then
            return 0
          end

          -- Contar caracteres comunes
          local common_chars = 0
          local str1_chars = {}

          for c in str1:gmatch(".") do
            str1_chars[c] = (str1_chars[c] or 0) + 1
          end

          for c in str2:gmatch(".") do
            if str1_chars[c] and str1_chars[c] > 0 then
              common_chars = common_chars + 1
              str1_chars[c] = str1_chars[c] - 1
            end
          end

          -- Calcular puntuación de similitud
          return common_chars / math.max(#str1, #str2)
        end

        -- Si la similitud es alta, agregar a la lista de duplicados
        local similarity = similarity_score(comment_content, doc_content)
        if similarity > 0.7 then
          table.insert(duplicates, {start = comment_start, end_line = comment_end, similarity = similarity})
        end
      end

      i = comment_end + 1
    else
      i = i + 1
    end
  end

  -- Si hay duplicados y están cerca de donde vamos a insertar, eliminamos el duplicado
  if #duplicates > 0 then
    -- Buscar el duplicado más cercano a la línea de inicio
    local closest_duplicate = nil
    local min_distance = math.huge

    for _, dup in ipairs(duplicates) do
      local distance = math.abs(dup.start - start_line)
      if distance < min_distance then
        min_distance = distance
        closest_duplicate = dup
      end
    end

    -- Si el duplicado está a menos de 20 líneas, eliminarlo
    if closest_duplicate and min_distance < 20 then
      log.warn("Eliminando documentación duplicada en líneas " .. closest_duplicate.start .. "-" .. closest_duplicate.end_line ..
              " (similitud: " .. string.format("%.2f", closest_duplicate.similarity) .. ")")
      vim.api.nvim_buf_set_lines(buffer, closest_duplicate.start - 1, closest_duplicate.end_line, false, {})

      -- Ajustar la línea de inicio si es necesario
      if closest_duplicate.start < start_line then
        start_line = start_line - (closest_duplicate.end_line - closest_duplicate.start + 1)
        if start_line < 1 then start_line = 1 end
      end
    end
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

  -- Verificar si hay duplicados que se hayan generado durante la sincronización
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(buffer) then
      return
    end

    local post_update_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local comment_blocks = {}

    -- Buscar todos los bloques de comentarios
    local i = 1
    while i <= #post_update_lines do
      local line = post_update_lines[i]

      if line:match("^%s*#") or line:match("^%s*=begin") then
        local block_start = i
        local block_end = i
        local is_block_comment = line:match("^%s*=begin") ~= nil
        local block_lines = {line}

        for j = i + 1, math.min(i + 30, #post_update_lines) do
          if is_block_comment then
            table.insert(block_lines, post_update_lines[j])
            block_end = j
            if post_update_lines[j]:match("^%s*=end") then
              break
            end
          elseif post_update_lines[j]:match("^%s*#") then
            table.insert(block_lines, post_update_lines[j])
            block_end = j
          else
            break
          end
        end

        if #block_lines >= 2 then
          table.insert(comment_blocks, {
            start = block_start,
            end_line = block_end,
            content = table.concat(block_lines, "\n")
          })
        end

        i = block_end + 1
      else
        i = i + 1
      end
    end

    -- Buscar bloques similares que estén cerca uno del otro
    for i = 1, #comment_blocks do
      for j = i + 1, #comment_blocks do
        -- Si los bloques están a menos de 20 líneas uno del otro
        if math.abs(comment_blocks[j].start - comment_blocks[i].end_line) < 20 then
          -- Función para calcular la similitud
          local function similarity_score(str1, str2)
            str1 = str1:gsub("%s+", "")
            str2 = str2:gsub("%s+", "")

            if #str1 > #str2 * 2 or #str2 > #str1 * 2 then
              return 0
            end

            local common_chars = 0
            local str1_chars = {}

            for c in str1:gmatch(".") do
              str1_chars[c] = (str1_chars[c] or 0) + 1
            end

            for c in str2:gmatch(".") do
              if str1_chars[c] and str1_chars[c] > 0 then
                common_chars = common_chars + 1
                str1_chars[c] = str1_chars[c] - 1
              end
            end

            return common_chars / math.max(#str1, #str2)
          end

          -- Calcular similitud
          local similarity = similarity_score(comment_blocks[i].content, comment_blocks[j].content)

          -- Si los bloques son muy similares, eliminar el segundo
          if similarity > 0.7 then
            log.warn("Eliminando documentación duplicada en líneas " .. comment_blocks[j].start .. "-" .. comment_blocks[j].end_line ..
                     " (similitud: " .. string.format("%.2f", similarity) .. ")")
            vim.api.nvim_buf_set_lines(buffer, comment_blocks[j].start - 1, comment_blocks[j].end_line, false, {})

            -- Ajustar índices de los bloques posteriores
            local lines_removed = comment_blocks[j].end_line - comment_blocks[j].start + 1
            for k = j + 1, #comment_blocks do
              comment_blocks[k].start = comment_blocks[k].start - lines_removed
              comment_blocks[k].end_line = comment_blocks[k].end_line - lines_removed
            end
          end
        end
      end
    end
  end, 100)

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
    if line:match("^%s*#") or line:match("^%s*=begin") then
      local doc_start = i
      local doc_end = i
      local comment_block = { line }
      local is_block_comment = line:match("^%s*=begin") ~= nil

      -- Buscar el final del bloque de comentarios
      for j = i + 1, math.min(i + 30, #lines) do
        if is_block_comment then
          table.insert(comment_block, lines[j])
          doc_end = j
          if lines[j]:match("^%s*=end") then
            break
          end
        elseif lines[j]:match("^%s*#") then
          table.insert(comment_block, lines[j])
          doc_end = j
        else
          break  -- Terminar si encontramos una línea que no es comentario
        end
      end

      -- Si el bloque es lo suficientemente largo y tiene tags YARD o RDoc
      if #comment_block >= 3 then
        local block_text = table.concat(comment_block, "\n")
        if block_text:match("@param") or block_text:match("@return") or
           block_text:match(":param:") or block_text:match(":returns?:") or
           block_text:match("==+ Parameters") or block_text:match("==+ Return") then
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