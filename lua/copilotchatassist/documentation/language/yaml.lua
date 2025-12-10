-- Manejador específico para documentación de YAML/Kubernetes
-- Extiende el manejador común con funcionalidades específicas para YAML/Kubernetes

local M = {}
local common = require("copilotchatassist.documentation.language.common")
local log = require("copilotchatassist.utils.log")

-- Heredar funcionalidad básica del manejador común
for k, v in pairs(common) do
  M[k] = v
end

-- Sobreescribir patrones para adaptarlos a YAML/Kubernetes
M.patterns = {
  -- Patrones específicos para YAML/Kubernetes
  resource_start = "^%s*kind:%s*([%w]+)",
  metadata_name = "^%s*name:%s*([%w%-%.]+)",
  api_version = "^%s*apiVersion:%s*([%w%/%.-]+)",
  namespace = "^%s*namespace:%s*([%w%-%.]+)",

  -- Recursos específicos de Kubernetes
  deployment = "^%s*kind:%s*Deployment",
  service = "^%s*kind:%s*Service",
  pod = "^%s*kind:%s*Pod",
  configmap = "^%s*kind:%s*ConfigMap",
  secret = "^%s*kind:%s*Secret",
  ingress = "^%s*kind:%s*Ingress",
  persistentvolume = "^%s*kind:%s*PersistentVolume[%w]*",
  daemonset = "^%s*kind:%s*DaemonSet",
  statefulset = "^%s*kind:%s*StatefulSet",
  job = "^%s*kind:%s*Job",
  cronjob = "^%s*kind:%s*CronJob",
  namespace_kind = "^%s*kind:%s*Namespace",
  serviceaccount = "^%s*kind:%s*ServiceAccount",

  -- Comentarios YAML
  comment_start = "^%s*#%s*",
  comment_line = "^%s*#%s?(.*)",
  yaml_separator = "^%s*---%s*$",

  -- Secciones comunes en manifiestos
  spec_section = "^%s*spec:%s*$",
  metadata_section = "^%s*metadata:%s*$",
  data_section = "^%s*data:%s*$",
  template_section = "^%s*template:%s*$",
}

-- Encuentra la línea de finalización de un recurso YAML/Kubernetes
-- @param lines tabla: Líneas del buffer
-- @param start_line número: Línea de inicio
-- @param item_type string: Tipo de elemento ("Deployment", "Service", etc)
-- @return número: Número de línea final o nil si no se puede determinar
function M.find_end_line(lines, start_line, item_type)
  if not lines or not start_line or start_line > #lines then
    return nil
  end

  local base_indent_level = nil
  local start_line_content = lines[start_line]

  -- En YAML, determinamos el nivel de indentación base
  if start_line_content then
    base_indent_level = #(start_line_content:match("^(%s*)") or "")
  end

  -- Buscar el final del documento YAML o el siguiente recurso
  for i = start_line + 1, #lines do
    local line = lines[i]

    -- Si encontramos un separador YAML (---), es el final del recurso actual
    if line:match(M.patterns.yaml_separator) then
      return i - 1
    end

    -- Si encontramos otro "kind:" al mismo nivel de indentación, es otro recurso
    if line:match(M.patterns.resource_start) then
      local this_indent = #(line:match("^(%s*)") or "")
      if this_indent == base_indent_level then
        return i - 1
      end
    end

    -- Si es una línea vacía, continuamos
    if line:match("^%s*$") then
      goto continue
    end

    -- Si encontramos una línea con contenido al mismo nivel de indentación que el inicio
    -- y no es parte del recurso actual, consideramos que es el final
    local current_indent = #(line:match("^(%s*)") or "")
    if current_indent == base_indent_level and
       not line:match("^%s*#") and
       not line:match(M.patterns.api_version) and
       not line:match(M.patterns.metadata_section) and
       not line:match(M.patterns.spec_section) then
      -- Verificamos si es otro recurso diferente
      if line:match("^%s*[%w]+:") and not line:match("^%s*kind:") then
        -- Es probable que sea parte del mismo recurso
        goto continue
      end
    end

    ::continue::
  end

  return #lines  -- Si no se puede determinar, devolver la última línea
end

-- Busca documentación en líneas de texto para YAML/Kubernetes
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

  -- Buscar comentarios justo antes del recurso
  local doc_end = start_idx - 1
  local doc_start = nil
  local doc_lines = {}

  for i = doc_end, min_idx, -1 do
    local line = lines[i]

    -- Saltarse líneas vacías inmediatas
    if not doc_start and line:match("^%s*$") then
      doc_end = i - 1
      goto continue
    end

    -- Saltarse separadores YAML
    if line:match(M.patterns.yaml_separator) then
      if doc_start then
        break
      end
      goto continue
    end

    -- Detectar comentarios YAML
    local is_comment_line = line:match(M.patterns.comment_start)
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

-- Escanea un buffer en busca de problemas de documentación en YAML/Kubernetes
-- @param buffer número: ID del buffer a escanear
-- @return tabla: Lista de elementos con problemas de documentación
function M.scan_buffer(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local items = {}
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  -- Buscar recursos de Kubernetes en YAML
  for i, line in ipairs(lines) do
    -- Omitir líneas de comentario en esta fase
    if line:match("^%s*#") then
      goto continue
    end

    -- Variables para almacenar información del recurso
    local resource_kind = nil
    local resource_name = nil
    local resource_namespace = nil
    local api_version = nil

    -- Detectar el tipo de recurso Kubernetes
    resource_kind = line:match(M.patterns.resource_start)

    if resource_kind then
      log.debug("Recurso Kubernetes detectado: " .. resource_kind .. " en línea " .. i)

      -- Buscar metadatos asociados (nombre, namespace) en las siguientes líneas
      local search_end = math.min(i + 20, #lines)
      for j = i + 1, search_end do
        local meta_line = lines[j]

        -- Si encontramos otro recurso, paramos
        if meta_line:match(M.patterns.resource_start) then
          break
        end

        -- Extraer nombre del recurso
        if not resource_name then
          resource_name = meta_line:match(M.patterns.metadata_name)
        end

        -- Extraer namespace
        if not resource_namespace then
          resource_namespace = meta_line:match(M.patterns.namespace)
        end

        -- Extraer apiVersion
        if not api_version then
          api_version = meta_line:match(M.patterns.api_version)
        end
      end

      -- Crear identificador del recurso
      local item_name = resource_kind
      if resource_name then
        item_name = resource_kind .. "/" .. resource_name
        if resource_namespace then
          item_name = resource_namespace .. "/" .. item_name
        end
      end

      -- Encontrar el final del recurso
      local end_line = M.find_end_line(lines, i, resource_kind)
      if not end_line then
        end_line = math.min(i + 50, #lines)  -- Los manifiestos pueden ser largos
      end

      -- Verificar si tiene documentación
      local doc_info = M.find_doc_block(lines, i)
      local has_doc = doc_info ~= nil

      -- Contenido del recurso
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
        -- Para YAML/Kubernetes, consideramos completa cualquier documentación existente
        -- Se podría mejorar con verificaciones más específicas en el futuro
        issue_type = nil
      end

      -- Si hay un problema, agregar a la lista
      if issue_type then
        table.insert(items, {
          name = item_name,
          type = "kubernetes_resource",
          subtype = resource_kind,
          bufnr = buffer,
          start_line = i,
          end_line = end_line,
          content = content,
          has_doc = has_doc,
          issue_type = issue_type,
          doc_start_line = has_doc and doc_info.start_line or nil,
          doc_end_line = has_doc and doc_info.end_line or nil,
          doc_lines = has_doc and doc_info.lines or nil,
          metadata = {
            kind = resource_kind,
            name = resource_name,
            namespace = resource_namespace,
            apiVersion = api_version
          },
          params = {}  -- Los recursos YAML no tienen parámetros formales
        })
      end
    end

    ::continue::
  end

  log.debug("Se encontraron " .. #items .. " recursos con problemas de documentación en el archivo YAML/Kubernetes")
  return items
end

-- Determina si la documentación de un recurso está desactualizada
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param resource_lines tabla: Líneas del recurso
-- @return boolean: true si está desactualizada, false en caso contrario
function M.is_documentation_outdated(buffer, doc_lines, resource_lines)
  -- Para YAML/Kubernetes, no implementamos verificación detallada de actualización
  -- Simplemente asumimos que está actualizada si existe
  return false
end

-- Determina si la documentación de un recurso está incompleta
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param param_names tabla: Nombres de los parámetros (no aplicable para YAML)
-- @return boolean: true si está incompleta, false en caso contrario
function M.is_documentation_incomplete(buffer, doc_lines, param_names)
  -- Para YAML/Kubernetes, no implementamos verificación detallada de completitud
  -- Simplemente asumimos que está completa si existe
  return false
end

-- Normaliza la documentación para YAML/Kubernetes
-- @param doc_block string: Bloque de documentación
-- @return string: Documentación normalizada
function M.normalize_documentation(doc_block)
  if not doc_block or doc_block == "" then
    return ""
  end

  -- Eliminar líneas vacías al inicio y al final
  doc_block = doc_block:gsub("^%s*(.-)%s*$", "%1")

  -- Asegurar que la documentación tenga el formato correcto para YAML
  local lines = vim.split(doc_block, "\n")
  local normalized_lines = {}

  -- Determinar si ya es un bloque de comentarios YAML
  local is_yaml_comment = false
  for _, line in ipairs(lines) do
    if line:match("^%s*#") then
      is_yaml_comment = true
      break
    end
  end

  -- Si ya tiene formato de comentarios YAML, usarlo como está
  if is_yaml_comment then
    return doc_block
  end

  -- Si no es un comentario, convertir a comentarios YAML (# ...)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      table.insert(normalized_lines, "# " .. line)
    else
      table.insert(normalized_lines, "#")
    end
  end

  return table.concat(normalized_lines, "\n")
end

-- Aplica documentación a un recurso en YAML/Kubernetes
-- @param buffer número: ID del buffer
-- @param start_line número: Línea antes de la cual insertar la documentación
-- @param doc_block string: Bloque de documentación a insertar
-- @return boolean: true si se aplicó correctamente, false en caso contrario
function M.apply_documentation(buffer, start_line, doc_block, item)
  if not doc_block or doc_block == "" then
    log.error("Bloque de documentación vacío")
    return false
  end

  -- Asegurar que la documentación esté en formato YAML
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

  -- En YAML, no aplicamos indentación adicional para comentarios al nivel raíz
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
    table.insert(doc_lines, "")  -- Añadir línea en blanco para separar del recurso
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

  -- Buscar bloques consecutivos de comentarios antes de recursos
  for i = 1, #lines - 1 do
    local line = lines[i]
    local next_line = lines[i + 1]

    -- Si encontramos un comentario seguido de un recurso Kubernetes
    if line:match("^%s*#") and next_line:match(M.patterns.resource_start) then

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
  end

  return examples
end

return M