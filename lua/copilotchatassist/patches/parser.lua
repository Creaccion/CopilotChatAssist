-- Módulo para parsear bloques de patches en respuestas de CopilotChat
-- Migrado y adaptado desde CopilotFiles

local M = {}
local log = require("copilotchatassist.utils.log")

-- Parsea texto para extraer bloques de patches
-- @param text string|table: Texto a parsear, puede ser string o tabla de líneas
-- @return table: Lista de patches encontrados
function M.parse_patches(text)
  local patches = {}
  local lines = type(text) == "string" and vim.split(text, "\n") or text
  local in_patch = false
  local patch = nil

  -- Patrón para detectar encabezado de patch
  local patch_header_pattern = "^```%w+ path=.+ start_line=%d+ end_line=%d+ mode=%w+"

  log.debug("Iniciando parseo de patches. Total de líneas: " .. tostring(#lines))
  for i, line in ipairs(lines) do
    if not in_patch and line:match(patch_header_pattern) then
      log.debug("Detectado encabezado de patch en línea " .. tostring(i) .. ": " .. line)
      in_patch = true
      local archivo = line:match("path=([^%s]+)")
      local start_line = tonumber(line:match("start_line=(%d+)"))
      local end_line = tonumber(line:match("end_line=(%d+)"))
      local modo = line:match("mode=(%w+)")
      patch = {
        header = line,
        archivo = archivo,
        start_line = start_line,
        end_line = end_line,
        modo = modo,
        content = {}
      }
    elseif in_patch and line == "```end" then
      log.debug("Detectado fin de patch en línea " .. tostring(i))
      in_patch = false
      patch.block = table.concat(patch.content, "\n")
      table.insert(patches, patch)
      log.debug("Patch parseado con encabezado: " .. patch.header)
      patch = nil
    elseif in_patch then
      table.insert(patch.content, line)
    end
  end

  log.debug("Total de patches parseados: " .. tostring(#patches))
  for idx, p in ipairs(patches) do
    log.debug("Patch #" .. idx .. " header: " .. p.header)
    log.debug("Patch #" .. idx .. " vista previa: " .. (p.block:sub(1, 100) .. (p.block:len() > 100 and "..." or "")))
  end

  return patches
end

-- Genera un hash único para un bloque de patch
-- @param patch table: El patch para el que generar un hash
-- @return string: Hash SHA-256 del contenido del patch
function M.generate_patch_hash(patch)
  if not patch or not patch.block then
    log.warn("Intento de generar hash para un patch inválido")
    return ""
  end

  -- Crear un string que combine archivo, modo y contenido para el hash
  local hash_input = (patch.archivo or "") .. "|" ..
                     (patch.modo or "") .. "|" ..
                     tostring(patch.start_line) .. "|" ..
                     tostring(patch.end_line) .. "|" ..
                     patch.block

  return vim.fn.sha256(hash_input)
end

return M