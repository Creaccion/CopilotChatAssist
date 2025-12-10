-- Módulo para detectar elementos que han cambiado usando git
-- Este módulo identifica funciones, métodos y clases que han sido modificados recientemente

local M = {}
local log = require("copilotchatassist.utils.log")

-- Obtiene las líneas que han cambiado en un archivo según git
-- @param file_path string: Ruta del archivo a verificar
-- @param opts table: Opciones adicionales (como número de commits a considerar)
-- @return table: Lista de rangos de líneas cambiados {start_line, end_line, type}
function M.get_changed_lines(file_path, opts)
  opts = opts or {}

  -- Número de commits a revisar (por defecto 1)
  local num_commits = opts.num_commits or 1

  -- Log para depuración
  log.debug("Ejecutando git diff para " .. file_path .. " con " .. num_commits .. " commits")

  -- Primero verificar si el archivo está en un repositorio git
  local check_cmd = string.format("git ls-files --error-unmatch %s",
                            vim.fn.shellescape(file_path))
  local check_output = vim.fn.system(check_cmd)
  if vim.v.shell_error ~= 0 then
    log.warn("El archivo no está en un repositorio git: " .. file_path)
    return {}
  end

  -- Ejecutar git diff para obtener las líneas modificadas
  local cmd = string.format("git diff HEAD~%d..HEAD --unified=0 -- %s",
                            num_commits, vim.fn.shellescape(file_path))

  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    -- Intentar con otro enfoque si falla el comando anterior
    cmd = string.format("git diff HEAD~%d --unified=0 -- %s",
                        num_commits, vim.fn.shellescape(file_path))
    output = vim.fn.system(cmd)

    if vim.v.shell_error ~= 0 then
      log.warn("Error al ejecutar git diff: " .. output)
      return {}
    end
  end

  -- Log para depuración
  log.debug("Resultado de git diff: " .. #output .. " bytes")

  -- Procesar el resultado para obtener los rangos de líneas
  local changed_ranges = {}

  -- Buscar líneas con formato @@ -a,b +c,d @@ donde c es línea de inicio y d es número de líneas
  for start_line, num_lines in string.gmatch(output, "@@ %-%d+,%d+ %+(%d+),(%d+) @@") do
    local start = tonumber(start_line)
    local count = tonumber(num_lines)
    if start and count and count > 0 then
      table.insert(changed_ranges, {
        start_line = start,
        end_line = start + count - 1,
        type = "modified"
      })
    end
  end

  -- También incluir líneas individuales
  for line in string.gmatch(output, "@@ %-%d+,%d+ %+(%d+) @@") do
    local line_num = tonumber(line)
    if line_num then
      table.insert(changed_ranges, {
        start_line = line_num,
        end_line = line_num,
        type = "modified"
      })
    end
  end

  return changed_ranges
end

-- Identifica elementos (funciones, métodos, clases) que han cambiado en un buffer
-- @param buffer number: ID del buffer a analizar
-- @param opts table: Opciones adicionales (como número de commits a considerar)
-- @return table: Lista de elementos detectados con información adicional
function M.detect_changed_elements(buffer, opts)
  opts = opts or {}
  local file_path = vim.api.nvim_buf_get_name(buffer)

  -- Verificar que es un archivo válido
  if not file_path or file_path == "" then
    log.warn("No se pudo obtener la ruta del archivo para el buffer " .. buffer)
    return {}
  end

  -- Registrar para depuración
  log.debug("Detectando cambios en git para buffer " .. buffer .. " (archivo: " .. file_path .. ")")

  -- Obtener los rangos de líneas cambiados
  local changed_ranges = M.get_changed_lines(file_path, opts)
  log.debug("Se encontraron " .. #changed_ranges .. " rangos de líneas modificados")

  if #changed_ranges == 0 then
    log.info("No se detectaron cambios recientes en el archivo " .. file_path)
    return {}
  end

  -- Obtener los elementos del archivo (funciones, métodos, etc.)
  local detector = require("copilotchatassist.documentation.detector")
  local elements = detector.scan_buffer(buffer)
  log.debug("Detector encontró " .. #elements .. " elementos en total")

  -- Marcar los elementos que se solapan con rangos cambiados
  local changed_elements = {}

  for _, element in ipairs(elements) do
    for _, range in ipairs(changed_ranges) do
      -- Verificar si el elemento está dentro del rango o se solapa con él
      if (element.start_line <= range.end_line and
          element.end_line >= range.start_line) then
        -- Añadir información de cambio al elemento
        element.changed = true
        element.change_type = range.type
        table.insert(changed_elements, element)
        break -- Ya encontramos un cambio para este elemento
      end
    end
  end

  log.debug("Se encontraron " .. #changed_elements .. " elementos modificados en " .. file_path)
  return changed_elements
end

-- Combina elementos detectados normalmente con los que han cambiado
-- @param normal_elements table: Elementos detectados por el detector estándar
-- @param changed_elements table: Elementos detectados como cambiados
-- @return table: Lista combinada con marcas de cambios
function M.combine_with_changes(normal_elements, changed_elements)
  -- Crear un mapa de elementos cambiados para búsqueda rápida
  local changed_map = {}
  for _, changed in ipairs(changed_elements) do
    local key = string.format("%s:%d-%d", changed.name, changed.start_line, changed.end_line)
    changed_map[key] = changed
  end

  -- Marcar elementos normales que estén en la lista de cambiados
  for i, element in ipairs(normal_elements) do
    local key = string.format("%s:%d-%d", element.name, element.start_line, element.end_line)
    if changed_map[key] then
      normal_elements[i].changed = true
      normal_elements[i].change_type = changed_map[key].change_type
    else
      normal_elements[i].changed = false
    end
  end

  -- Añadir elementos cambiados que no estén en la lista normal
  for _, changed in ipairs(changed_elements) do
    local key = string.format("%s:%d-%d", changed.name, changed.start_line, changed.end_line)
    local found = false

    for _, element in ipairs(normal_elements) do
      local elem_key = string.format("%s:%d-%d", element.name, element.start_line, element.end_line)
      if elem_key == key then
        found = true
        break
      end
    end

    if not found then
      table.insert(normal_elements, changed)
    end
  end

  return normal_elements
end

return M