-- Módulo especial para corregir problemas de documentación en Java
-- Este módulo contiene funciones para manejar casos específicos que causan problemas

local M = {}
local log = require("copilotchatassist.utils.log")

-- Función para documentar una clase Java con anotaciones
-- Esta función se usa cuando el detector normal no funciona correctamente
-- @param file_path string: Ruta del archivo a procesar
-- @param class_name string: Nombre de la clase a documentar
-- @param doc_block string: Bloque de documentación a insertar
-- @return boolean: true si tuvo éxito, false en caso contrario
function M.document_class_with_annotations(file_path, class_name, doc_block)
  local log_prefix = "[JAVA_FIXER] "
  log.info(log_prefix .. "Iniciando documentación especial para clase con anotaciones: " .. class_name)

  -- Leer el archivo
  local file, err = io.open(file_path, "r")
  if not file then
    log.error(log_prefix .. "No se pudo abrir el archivo: " .. err)
    return false
  end

  -- Leer contenido del archivo
  local content = file:read("*all")
  file:close()

  -- Buscar la clase y sus anotaciones
  local pattern = "@[%w_]+%s*[\r\n]%s*public%s+class%s+" .. class_name
  local match_start, match_end = content:find(pattern)

  if not match_start then
    log.error(log_prefix .. "No se encontró la clase con anotaciones: " .. class_name)
    return false
  end

  -- Encontrar el inicio de la anotación
  local annotation_start = content:sub(1, match_start):reverse():find("%s[\r\n]")
  if annotation_start then
    annotation_start = match_start - annotation_start + 2
  else
    annotation_start = match_start
  end

  -- Insertar la documentación antes de la anotación
  local new_content = content:sub(1, annotation_start - 1) ..
                     doc_block .. "\n" ..
                     content:sub(annotation_start)

  -- Escribir el archivo
  file, err = io.open(file_path, "w")
  if not file then
    log.error(log_prefix .. "No se pudo abrir el archivo para escribir: " .. err)
    return false
  end

  file:write(new_content)
  file:close()

  log.info(log_prefix .. "Documentación aplicada correctamente para la clase: " .. class_name)
  return true
end

-- Función para documentar directamente una clase Java usando una solución alternativa
-- @param buffer número: ID del buffer
-- @param class_name string: Nombre de la clase a documentar
-- @param doc_block string: Bloque de documentación a insertar
-- @return boolean: true si tuvo éxito, false en caso contrario
function M.document_class_directly(buffer, class_name, doc_block)
  local log_prefix = "[JAVA_FIXER] "
  log.info(log_prefix .. "Iniciando documentación directa para clase: " .. class_name)

  -- Verificar buffer válido
  if not vim.api.nvim_buf_is_valid(buffer) then
    log.error(log_prefix .. "Buffer inválido")
    return false
  end

  -- Leer el contenido del buffer
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

  -- Buscar la anotación y la clase
  local annotation_line = nil
  local class_line = nil

  for i, line in ipairs(lines) do
    if line:match("^%s*@[%w_]+") then
      -- Verificar si la siguiente línea contiene la definición de clase
      if i < #lines and lines[i+1]:match("public%s+class%s+" .. class_name) then
        annotation_line = i
        class_line = i + 1
        break
      end
    end

    if line:match("public%s+class%s+" .. class_name) then
      class_line = i
      break
    end
  end

  if not class_line then
    log.error(log_prefix .. "No se encontró la clase: " .. class_name)
    return false
  end

  -- Determinar dónde insertar la documentación
  local insert_line = annotation_line or class_line

  -- Convertir documentación a líneas
  local doc_lines = {}
  for line in doc_block:gmatch("[^\r\n]+") do
    table.insert(doc_lines, line)
  end

  -- Insertar documentación
  vim.api.nvim_buf_set_lines(buffer, insert_line - 1, insert_line - 1, false, doc_lines)

  log.info(log_prefix .. "Documentación aplicada correctamente en la línea: " .. insert_line)
  return true
end

return M