-- Utility module for file and directory operations

local M = {}

-- Write content to a file at the given path
-- @param path string: ruta del archivo
-- @param content string|table: contenido a escribir
-- @param force boolean: si es true, intenta métodos alternativos de escritura si el método estándar falla
-- @return boolean: true si tuvo éxito, false en caso contrario
function M.write_file(path, content, force)
  local file = io.open(path, "w")
  if file then
    -- Si content es una tabla o parece un JSON
    if type(content) == "table" then
      if content.content then
        content = content.content
      else
        content = vim.inspect(content)
      end
    elseif type(content) == "string" and content:match("^%s*{.*}%s*$") then
      -- Intentar extraer el campo 'content' de un string con formato JSON/Lua
      local utils = require("copilotchatassist.utils")
      local extracted = nil

      -- Primer intento: evaluar como tabla Lua
      if utils.try_evaluate_lua_table then
        local tab = utils.try_evaluate_lua_table(content)
        if tab and tab.content and type(tab.content) == "string" then
          extracted = tab.content
        end
      end

      -- Segundo intento: extraer mediante regex
      if not extracted then
        local content_match = content:match('content%s*=%s*"(.-)"') or
                              content:match('"content":%s*"(.-)"')
        if content_match then
          extracted = content_match
        end
      end

      -- Si se extrajo contenido, usarlo
      if extracted then
        content = extracted
      end
    end

    -- Buscar bloques de código en el contenido
    if content and type(content) == "string" and content:match("```") then
      local utils = require("copilotchatassist.utils")
      if utils.extract_code_block then
        local code_block = utils.extract_code_block(content)
        if code_block and code_block ~= "" then
          content = code_block
        end
      end
    end

    -- Verificar que content sea string antes de escribir
    if type(content) ~= "string" then
      content = vim.inspect(content)
    end

    -- Guardar el contenido en un archivo de diagnóstico
    local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    vim.fn.mkdir(debug_dir, "p")
    local debug_file = debug_dir .. "/last_write_content.txt"
    local debug_f = io.open(debug_file, "w")
    if debug_f then
      debug_f:write("Path: " .. path .. "\n")
      debug_f:write("Content type: " .. type(content) .. "\n")
      debug_f:write("Content length: " .. #content .. " bytes\n")
      debug_f:write("Content: \n" .. content)
      debug_f:close()
    end

    -- Escribir el contenido final al archivo
    local success, err = pcall(function()
      file:write(content)
      file:close()
    end)

    if success then
      return true
    else
      -- Intentar método alternativo si force es true
      if force then
        -- Usar vim para escribir el archivo
        local temp_buf = vim.api.nvim_create_buf(false, true)
        if temp_buf and vim.api.nvim_buf_is_valid(temp_buf) then
          -- Dividir el contenido en líneas
          local lines = {}
          for line in content:gmatch("([^\n]*)\n?") do
            table.insert(lines, line)
          end

          -- Establecer las líneas en el buffer
          vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines)

          -- Guardar el buffer en el archivo
          local saved = pcall(function()
            vim.api.nvim_command('silent write! ' .. vim.fn.fnameescape(path))
          end)

          -- Limpiar el buffer temporal
          vim.api.nvim_buf_delete(temp_buf, { force = true })

          return saved
        end
      end
      return false
    end
  else
    -- Intentar método alternativo si force es true y el archivo no se pudo abrir
    if force then
      -- Método 1: Usar comando del sistema para escribir el archivo
      local temp_file = os.tmpname()
      local tmp = io.open(temp_file, "w")
      if tmp then
        tmp:write(content)
        tmp:close()

        -- Guardar información de diagnóstico
        local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
        vim.fn.mkdir(debug_dir, "p")
        local sys_debug_file = debug_dir .. "/system_write_debug.txt"
        local sys_debug_f = io.open(sys_debug_file, "w")
        if sys_debug_f then
          sys_debug_f:write("Temp file: " .. temp_file .. "\n")
          sys_debug_f:write("Target path: " .. path .. "\n")
          sys_debug_f:write("Content length: " .. #content .. " bytes\n")
          sys_debug_f:close()
        end

        -- Intentar varios métodos de copia
        -- 1. cp normal
        local cp_cmd = string.format("cp %s %s",
          vim.fn.shellescape and vim.fn.shellescape(temp_file) or temp_file,
          vim.fn.shellescape and vim.fn.shellescape(path) or path)
        local result = os.execute(cp_cmd)

        -- Verificar si funcionó
        if result == 0 or result == true then
          os.remove(temp_file)
          return true
        end

        -- 2. Usar cat con redirección
        local cat_cmd = string.format("cat %s > %s",
          vim.fn.shellescape and vim.fn.shellescape(temp_file) or temp_file,
          vim.fn.shellescape and vim.fn.shellescape(path) or path)
        result = os.execute(cat_cmd)

        if result == 0 or result == true then
          os.remove(temp_file)
          return true
        end

        -- 3. Usar tee que puede manejar permisos diferentes
        local tee_cmd = string.format("cat %s | tee %s >/dev/null",
          vim.fn.shellescape and vim.fn.shellescape(temp_file) or temp_file,
          vim.fn.shellescape and vim.fn.shellescape(path) or path)
        result = os.execute(tee_cmd)

        -- Verificar resultado
        if sys_debug_f then
          local sys_debug_f = io.open(sys_debug_file, "a")
          if sys_debug_f then
            sys_debug_f:write("cp command: " .. cp_cmd .. ", result: " .. tostring(result) .. "\n")
            sys_debug_f:write("cat command: " .. cat_cmd .. ", result: " .. tostring(result) .. "\n")
            sys_debug_f:write("tee command: " .. tee_cmd .. ", result: " .. tostring(result) .. "\n")
            sys_debug_f:close()
          end
        end

        os.remove(temp_file)
        if result == 0 or result == true then
          return true
        end
      end

      -- Método 2: Usar comandos de Neovim para escribir el archivo
      local write_success = pcall(function()
        -- Crear un buffer temporal
        local temp_buf = vim.api.nvim_create_buf(false, true)
        if temp_buf and vim.api.nvim_buf_is_valid(temp_buf) then
          -- Dividir el contenido en líneas
          local lines = {}
          for line in content:gmatch("([^\n]*)\n?") do
            table.insert(lines, line)
          end

          -- Establecer las líneas en el buffer
          vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines)

          -- Asociar el buffer con el archivo
          vim.api.nvim_buf_set_name(temp_buf, path)

          -- Guardar el buffer directamente
          vim.cmd('silent! buffer ' .. temp_buf)
          vim.cmd('silent! write! ' .. vim.fn.fnameescape(path))
          vim.cmd('silent! bdelete! ' .. temp_buf)
          return true
        end
      end)

      if write_success then
        return true
      end
    end
    return false
  end
end

-- Read content from a file
function M.read_file(path)
  local file = io.open(path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    return content
  end
  return nil
end

-- Create a directory if it does not exist
function M.ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

return M
