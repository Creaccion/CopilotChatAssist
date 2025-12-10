-- Comandos para CopilotChatAssist
local M = {}
local log = require("copilotchatassist.utils.log")
local copilotchat_api = require("copilotchatassist.copilotchat_api")
local options = require("copilotchatassist.options")
local i18n = require("copilotchatassist.i18n")

-- Registrar todos los comandos
function M.setup()
  vim.api.nvim_create_user_command("CopilotChatCheckConnection", function()
    M.check_connection()
  end, {
    desc = "Verificar la conexión con CopilotChat"
  })

  vim.api.nvim_create_user_command("CopilotChatDebugLogs", function()
    M.show_debug_logs()
  end, {
    desc = "Mostrar los logs de depuración de CopilotChatAssist"
  })

  vim.api.nvim_create_user_command("CopilotChatLogLevel", function(opts)
    M.change_log_level(opts.args)
  end, {
    desc = "Cambiar el nivel de log (ERROR, WARN, INFO, DEBUG, TRACE)",
    nargs = "?",
    complete = function()
      return {"ERROR", "WARN", "INFO", "DEBUG", "TRACE"}
    end
  })

  vim.api.nvim_create_user_command("CopilotChatLanguage", function(opts)
    M.change_language(opts.args)
  end, {
    desc = "Cambiar el idioma de la interfaz (english, spanish)",
    nargs = "?",
    complete = function()
      return {"english", "spanish"}
    end
  })
end

-- Verificar la conexión con CopilotChat
function M.check_connection()
  vim.notify("Verificando conexión con CopilotChat...", vim.log.levels.INFO)

  -- Intentar una solicitud simple para verificar la conexión
  copilotchat_api.ask("Hola, responde con 'conectado' si estás disponible.", {
    callback = function(response)
      if response and response ~= "" then
        vim.notify("CopilotChat está conectado y funcionando correctamente", vim.log.levels.INFO)
        vim.notify("Respuesta: " .. response:sub(1, 100) .. (response:len() > 100 and "..." or ""), vim.log.levels.INFO)
      else
        vim.notify("CopilotChat respondió con una respuesta vacía", vim.log.levels.ERROR)
      end
    end
  })
end

-- Cambiar el nivel de log
function M.change_log_level(level_name)
  if not level_name or level_name == "" then
    -- Mostrar configuración actual
    log.show_config()
    return
  end

  -- Convertir a mayúsculas para mejor comparación
  level_name = level_name:upper()

  -- Mapeo de nombres a niveles
  local level_mapping = {
    ERROR = vim.log.levels.ERROR,
    WARN = vim.log.levels.WARN,
    INFO = vim.log.levels.INFO,
    DEBUG = vim.log.levels.DEBUG,
    TRACE = vim.log.levels.TRACE
  }

  -- Verificar si el nivel es válido
  if not level_mapping[level_name] then
    vim.notify("Nivel de log no válido: " .. level_name .. ". Opciones válidas: ERROR, WARN, INFO, DEBUG, TRACE", vim.log.levels.ERROR)
    return
  end

  -- Actualizar la configuración
  options.set({ log_level = level_mapping[level_name] })

  -- Notificar el cambio
  vim.notify("Nivel de log cambiado a: " .. level_name, vim.log.levels.INFO)

  -- Mostrar la nueva configuración
  log.show_config()
end

-- Cambiar el idioma
function M.change_language(lang)
  if not lang or lang == "" then
    -- Mostrar configuración actual
    local current_lang = i18n.get_current_language()
    local current_code_lang = i18n.get_code_language()
    vim.notify("Idioma actual: " .. current_lang .. " (código: " .. current_code_lang .. ")", vim.log.levels.INFO)
    return
  end

  -- Verificar si el idioma es válido
  if not i18n.supported_languages[lang] then
    vim.notify("Idioma no válido: " .. lang .. ". Opciones válidas: english, spanish", vim.log.levels.ERROR)
    return
  end

  -- Guardar idioma anterior
  local old_lang = i18n.get_current_language()

  -- Actualizar la configuración
  options.set({ language = lang })

  -- Notificar el cambio
  if old_lang ~= lang then
    vim.notify("Idioma cambiado de " .. old_lang .. " a " .. lang, vim.log.levels.INFO)
  else
    vim.notify("El idioma ya está configurado como: " .. lang, vim.log.levels.INFO)
  end
end

-- Mostrar los logs de depuración
function M.show_debug_logs()
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  local log_files = {
    debug_dir .. "/response_raw.txt",
    debug_dir .. "/last_prompt.txt",
    debug_dir .. "/error_nil_response.txt",
    debug_dir .. "/error_empty_response.txt",
    debug_dir .. "/last_response.txt"
  }

  -- Verificar si algún archivo existe
  local found = false
  for _, file_path in ipairs(log_files) do
    if vim.fn.filereadable(file_path) == 1 then
      found = true
      break
    end
  end

  if not found then
    vim.notify("No se encontraron archivos de log de depuración", vim.log.levels.WARN)
    return
  end

  -- Crear un buffer flotante para los logs
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Preparar contenido del buffer
  local lines = {"=== LOGS DE DEPURACIÓN COPILOTCHATASSIST ===", ""}

  -- Añadir contenido de cada archivo de log si existe
  for _, file_path in ipairs(log_files) do
    if vim.fn.filereadable(file_path) == 1 then
      local file_name = vim.fn.fnamemodify(file_path, ":t")
      table.insert(lines, "=== " .. file_name .. " ===")

      local file = io.open(file_path, "r")
      if file then
        local content = file:read("*all")
        file:close()

        -- Limitar a 500 líneas por archivo para evitar buffers demasiado grandes
        local content_lines = {}
        for line in content:gmatch("[^\n]+") do
          table.insert(content_lines, line)
          if #content_lines >= 500 then
            table.insert(content_lines, "... (truncado, más líneas disponibles en " .. file_path .. ")")
            break
          end
        end

        for _, line in ipairs(content_lines) do
          table.insert(lines, line)
        end
      else
        table.insert(lines, "Error: No se pudo abrir el archivo")
      end

      table.insert(lines, "")
    end
  end

  -- Mostrar en el buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded"
  })

  -- Configurar el buffer
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_name(buf, "CopilotChat Debug Logs")

  -- Cerrar con 'q'
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q<CR>', { noremap = true, silent = true })
end

return M