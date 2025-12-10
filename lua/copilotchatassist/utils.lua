-- Utility functions for CopilotChatAssist

local M = {}

local string_utils = require("copilotchatassist.utils.string")
local file_utils = require("copilotchatassist.utils.file")
local buffer_utils = require("copilotchatassist.utils.buffer")
local log = require("copilotchatassist.utils.log")

-- Re-export string_utils functions
M.trim = string_utils.trim
M.truncate_string = string_utils.truncate_string

-- Get the current branch name
function M.get_current_branch()
  local handle = io.popen("git rev-parse --abbrev-ref HEAD")
  local branch = handle:read("*a"):gsub("%s+", "")
  handle:close()
  return branch
end

-- Get the project name (from cwd)
function M.get_project_name()
  local cwd = vim.fn.getcwd()
  return vim.fn.fnamemodify(cwd, ':t')
end

-- Generate a hash from a string (for branch names)
function M.hash_string(str)
  local hash = 0
  for i = 1, #str do
    hash = (hash * 31 + str:byte(i)) % 1000000007
  end
  return tostring(hash)
end

-- Get the current visual selection as a string
function M.get_visual_selection()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return ""
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row = start_pos[2] - 1
  local end_row = end_pos[2]
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
  if #lines == 0 then
    return ""
  end
  lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  lines[1] = string.sub(lines[1], start_pos[3], #lines[1])
  return table.concat(lines, "\n")
end

-- Intentar evaluar una cadena como una tabla de Lua
-- @param str string: Cadena que podría representar una tabla de Lua
-- @return table|nil: Tabla evaluada o nil si no se pudo evaluar
function M.try_evaluate_lua_table(str)
  if not str or type(str) ~= "string" then
    return nil
  end

  -- Verificar que parece una tabla de Lua
  if not str:match("^%s*{.+}%s*$") then
    return nil
  end

  -- Intentar evaluar de forma segura
  local success, result

  -- Primero intentar con loadstring (más viejo pero más compatible)
  if loadstring then
    local fn, err = loadstring("return " .. str)
    if fn then
      success, result = pcall(fn)
    end
  end

  -- Si no funcionó, intentar con load (más nuevo)
  if not success and load then
    local fn, err = load("return " .. str, "eval", "t", {})
    if fn then
      success, result = pcall(fn)
    end
  end

  -- Verificar que el resultado es una tabla
  if success and type(result) == "table" then
    return result
  end

  return nil
end

-- Extraer bloques de código de una cadena de texto
-- @param text string: Texto que puede contener bloques de código
-- @param options table: Opciones adicionales (opcional)
-- @return string: Primer bloque de código encontrado o cadena vacía si no hay bloques
function M.extract_code_block(text, options)
  options = options or {}
  if not text or text == "" then
    return ""
  end

  -- Detectar si la entrada es JSON o tabla Lua
  if text:match("^%s*{.*}%s*$") then
    log.debug("Detectado posible formato JSON o tabla Lua en extract_code_block")

    -- Intentar evaluar como tabla Lua (método más robusto)
    local lua_table = M.try_evaluate_lua_table(text)
    if lua_table and lua_table.content and type(lua_table.content) == "string" then
      log.debug("Evaluación exitosa como tabla Lua, usando campo 'content'")
      text = lua_table.content
    else
      -- Intentar con expresiones regulares como respaldo
      -- Primera opción: Formato JSON estándar
      local content_match = text:match('"content":%s*"(.-)"')

      -- Segunda opción: Formato de tabla Lua con content = "valor"
      if not content_match then
        content_match = text:match('content%s*=%s*"(.-)"')
      end

      -- Tercera opción: Formato de tabla Lua con content = [==[valor]==]
      if not content_match then
        content_match = text:match('content%s*=%s*%[=*%[(.-)%]=*%]')
      end

      -- Cuarta opción: Formato de tabla Lua con content = ```valor```
      if not content_match then
        content_match = text:match('content%s*=%s*```(.-)```')
      end

      -- Si encontramos el campo content, usarlo como texto principal
      if content_match then
        log.debug("Extraído campo 'content' en extract_code_block usando regex")
        text = content_match

        -- Si el content tiene caracteres de escape para comillas, reemplazarlos
        text = text:gsub('\\"', '"')
      end
    end
  end

  -- Buscar bloques de código delimitados por ``` con etiqueta de lenguaje
  local code_block = nil
  local largest_block = ""
  local largest_block_size = 0

  -- Buscar formato de patch específico utilizando procesamiento manual
  -- Intentamos detectar patrones como ```lenguaje path=PATH start_line=N end_line=M mode=MODE
  for lang in text:gmatch("```([%w_]+)%s+path=") do
    local start_marker = "```" .. lang .. " path="
    local end_marker = "``` end"

    local start_pos = text:find(start_marker, 1, true)
    local end_pos = text:find(end_marker, 1, true)

    if start_pos and end_pos then
      local content_start = text:find("\n", start_pos) + 1
      local content_end = end_pos - 1

      if content_start < content_end then
        local content = text:sub(content_start, content_end)
        -- Eliminar posible salto de línea extra al final
        content = content:gsub("\n$", "")
        log.debug("Encontrado bloque de código en formato patch para " .. lang)
        return content
      end
    end
  end

  -- Intentar capturar bloques de código con formato ```lenguaje\ncontenido\n```
  local pattern = "```([%w_]*)\n(.-)\n```"
  local pos = 1
  while pos <= #text do
    local lang_start, lang_end, language, block = text:find(pattern, pos)
    if not lang_start then break end

    pos = lang_end + 1

    if block and #block > largest_block_size then
      largest_block = block
      largest_block_size = #block
      log.debug("Encontrado bloque de código con lenguaje: " .. (language ~= "" and language or "desconocido"))
    end
  end

  if largest_block_size > 0 then
    code_block = largest_block
    return code_block
  end

  -- Si no se encuentra un bloque de código con marcadores estándar, probar otras técnicas
  -- Buscar utilizando posiciones absolutas
  local start_pos = text:find("```[%w_]*\n")
  if start_pos then
    -- Avanzar después de los acentos graves y el salto de línea
    local content_start = text:find("\n", start_pos) + 1
    if content_start then
      -- Buscar el cierre del bloque
      local end_pos = text:find("\n```", content_start)
      if end_pos then
        code_block = text:sub(content_start, end_pos - 1)
        log.debug("Encontrado bloque de código mediante búsqueda por posición")
        return code_block
      end
    end
  end

  -- Si aún no se encuentra, intentar devolver todo el texto (podría ser solo código)
  if text:match("%S") and text:match("[{}()=;]") then
    log.debug("Devolviendo todo el texto como código")
    return text
  end

  -- Imprimir resultado para depuración
  log.error("No se pudo extraer ningún bloque de código")
  return ""

end

return M
