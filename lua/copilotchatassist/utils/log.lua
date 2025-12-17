-- Módulo de log mejorado para CopilotChatAssist con soporte para log_level configurable
local M = {}
local options = require("copilotchatassist.options")

-- Niveles de log para compatibilidad
M.levels = {
  ERROR = vim.log.levels.ERROR,
  WARN = vim.log.levels.WARN,
  INFO = vim.log.levels.INFO,
  DEBUG = vim.log.levels.DEBUG,
  TRACE = vim.log.levels.TRACE
}

-- Nombres de los niveles para depuración
M.level_names = {
  [vim.log.levels.ERROR] = "ERROR",
  [vim.log.levels.WARN] = "WARN",
  [vim.log.levels.INFO] = "INFO",
  [vim.log.levels.DEBUG] = "DEBUG",
  [vim.log.levels.TRACE] = "TRACE"
}

-- Función auxiliar para obtener el nivel de log configurado
-- @return number: Nivel de log configurado
local function get_log_level()
  local configured_level = options.get().log_level

  -- Forzar nivel ERROR o menor si se configura -1
  if configured_level == -1 then
    return -1  -- Nivel más restrictivo que ERROR
  end

  -- Asegurar que el valor es un número
  if type(configured_level) == "string" then
    -- Convertir strings a sus equivalentes numéricos
    local level_mapping = {
      ERROR = vim.log.levels.ERROR,
      WARN = vim.log.levels.WARN,
      INFO = vim.log.levels.INFO,
      DEBUG = vim.log.levels.DEBUG,
      TRACE = vim.log.levels.TRACE,
    }
    configured_level = level_mapping[configured_level:upper()] or vim.log.levels.INFO
  elseif type(configured_level) ~= "number" then
    -- Si no es string ni número, usar valor por defecto
    configured_level = vim.log.levels.INFO
  end

  -- Nunca permitir nivel DEBUG si el usuario estableció WARN o menor
  -- y no estamos en modo debug forzado
  if vim.g.copilotchatassist_force_debug ~= true and configured_level < vim.log.levels.DEBUG then
    vim.g.copilotchatassist_debug = false
  end

  return configured_level
end

-- Función para verificar si un nivel de log debe ser mostrado
-- @param level number: Nivel del mensaje de log
-- @return boolean: true si el mensaje debe ser mostrado, false en caso contrario
local function should_log(level)
  -- Si el nivel es -1, no mostrar ningún log excepto forzados
  if options.get().log_level == -1 and not vim.g.copilotchatassist_force_log then
    return false
  end

  local configured_level = get_log_level()

  -- Asegurar que level es un número válido
  if type(level) ~= "number" then
    -- Convertir strings a niveles si es posible
    if type(level) == "string" then
      local level_mapping = {
        ERROR = vim.log.levels.ERROR,
        WARN = vim.log.levels.WARN,
        INFO = vim.log.levels.INFO,
        DEBUG = vim.log.levels.DEBUG,
        TRACE = vim.log.levels.TRACE
      }
      level = level_mapping[level:upper()] or vim.log.levels.INFO
    else
      -- Si no es ni string ni número, usar INFO como default
      level = vim.log.levels.INFO
    end
  end

  -- Importante: los mensajes de DEBUG requieren que copilotchatassist_debug sea true
  -- o que el nivel de log sea DEBUG o superior
  if level == vim.log.levels.DEBUG and vim.g.copilotchatassist_debug ~= true and
     configured_level < vim.log.levels.DEBUG then
    return false
  end

  -- Los niveles más bajos son más prioritarios (ERROR = 0, TRACE = 4)
  return level <= configured_level
end

-- Función para obtener mensajes traducidos según el idioma configurado
-- @param messages table: Tabla con traducciones en formato {english = "...", spanish = "..."}
-- @return string: Mensaje en el idioma configurado
local function get_translated_message(messages)
  local lang = options.get().language or "english"
  -- Default a inglés si el idioma no existe en la tabla de mensajes
  return messages[lang] or messages["english"]
end

-- Función de log genérica
-- @param msg string|table: Mensaje a loguear o tabla con traducciones {english = "...", spanish = "..."}
-- @param level number: Nivel de log del mensaje
function M.log(msg, level)
  level = level or vim.log.levels.INFO

  -- Verificar si este nivel debe ser logueado
  if not should_log(level) then
    return
  end

  -- Si el mensaje es una tabla de traducciones, obtener la traducción correspondiente
  if type(msg) == "table" and (msg.english or msg.spanish) then
    msg = get_translated_message(msg)
  -- Convertir otros objetos no string a string
  elseif type(msg) ~= "string" then
    msg = vim.inspect(msg)
  end

  -- Prefijo para todos los mensajes
  local prefix = "[CopilotChatAssist]"

  -- Añadir el nivel al prefijo en modo debug o trace para mayor claridad
  if get_log_level() >= vim.log.levels.DEBUG then
    prefix = prefix .. "[" .. (M.level_names[level] or "UNKNOWN") .. "]"
  end

  -- Siempre usar print para el log en consola
  print(prefix .. " " .. msg)

  -- Escribir también al buffer de mensajes si el nivel es DEBUG o superior
  if get_log_level() >= vim.log.levels.DEBUG then
    -- Usar vim.notify para mensajes de DEBUG y nivel superior para garantizar visibilidad
    local msg_type = level
    if level > vim.log.levels.WARN then
      -- Convertir DEBUG y TRACE a INFO para vim.notify para que sean visibles
      msg_type = vim.log.levels.INFO
    end

    vim.notify(prefix .. " " .. msg, msg_type)

    -- También añadir a la ventana de mensajes
    vim.api.nvim_echo({{prefix .. " " .. msg, level == vim.log.levels.ERROR and "ErrorMsg" or
                                         level == vim.log.levels.WARN and "WarningMsg" or
                                         "Comment"}}, true, {})

    -- Forzar una actualización de la UI
    vim.cmd("redraw")
  end

  -- También escribir a archivo de log
  local log_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(log_dir, "p")
  local log_file = log_dir .. "/copilot_log.txt"

  local file = io.open(log_file, "a")
  if file then
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    file:write(timestamp .. " " .. prefix .. " " .. msg .. "\n")
    file:close()
  end

  -- Escribir también al buffer de mensajes si el nivel es DEBUG o superior
  if get_log_level() >= vim.log.levels.DEBUG and level <= vim.log.levels.WARN then
    vim.api.nvim_echo({{prefix .. " " .. msg, level == vim.log.levels.ERROR and "ErrorMsg" or
                                           level == vim.log.levels.WARN and "WarningMsg" or
                                           "Comment"}}, true, {})
  end
end

-- Funciones específicas por nivel
function M.error(msg)
  M.log(msg, vim.log.levels.ERROR)
end

function M.warn(msg)
  M.log(msg, vim.log.levels.WARN)
end

function M.info(msg)
  -- Si el nivel configurado es WARN o menor, no mostrar INFO
  if options.get().log_level <= vim.log.levels.WARN then
    -- Sólo escribir al archivo de log, sin pasar por notificaciones
    local log_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    vim.fn.mkdir(log_dir, "p")
    local log_file = log_dir .. "/copilot_log.txt"

    local file = io.open(log_file, "a")
    if file then
      local timestamp = os.date("%Y-%m-%d %H:%M:%S")
      local prefix = "[CopilotChatAssist][INFO]"

      -- Extraer el mensaje si es una tabla con traducciones
      if type(msg) == "table" and (msg.english or msg.spanish) then
        msg = msg[options.get().language or "english"] or msg.english or msg.spanish or "info message"
      -- Convertir objetos no string a string
      elseif type(msg) ~= "string" then
        msg = vim.inspect(msg)
      end

      file:write(timestamp .. " " .. prefix .. " " .. msg .. "\n")
      file:close()
    end

    return
  end

  -- Si el nivel configurado es INFO o mayor, usar el log normal
  M.log(msg, vim.log.levels.INFO)
end

function M.debug(msg)
  -- No mostrar mensajes de debug como notificaciones, NUNCA
  -- Sólo escribir al archivo de log

  -- Extraer el mensaje si es una tabla con traducciones
  if type(msg) == "table" and (msg.english or msg.spanish) then
    msg = msg[options.get().language or "english"] or msg.english or msg.spanish or "debug message"
  -- Convertir objetos no string a string
  elseif type(msg) ~= "string" then
    msg = vim.inspect(msg)
  end

  -- Escribir directamente al archivo de log sin usar M.log para evitar notificaciones
  local log_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(log_dir, "p")
  local log_file = log_dir .. "/copilot_log.txt"

  local file = io.open(log_file, "a")
  if file then
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local prefix = "[CopilotChatAssist][DEBUG]"
    file:write(timestamp .. " " .. prefix .. " " .. msg .. "\n")
    file:close()
  end
end

function M.trace(msg)
  M.log(msg, vim.log.levels.TRACE)
end

-- Registrar configuración actual de logs
function M.get_current_config()
  local current_level = get_log_level()
  local level_name = M.level_names[current_level] or "UNKNOWN"

  return {
    level = current_level,
    level_name = level_name,
    will_show = {
      error = should_log(vim.log.levels.ERROR),
      warn = should_log(vim.log.levels.WARN),
      info = should_log(vim.log.levels.INFO),
      debug = should_log(vim.log.levels.DEBUG),
      trace = should_log(vim.log.levels.TRACE)
    }
  }
end

-- Función para mostrar la configuración actual de logs
function M.show_config()
  local config = M.get_current_config()
  M.log("Nivel de log actual: " .. config.level_name .. " (" .. config.level .. ")", vim.log.levels.INFO)

  local levels_shown = {}
  for level, shown in pairs(config.will_show) do
    if shown then
      table.insert(levels_shown, level)
    end
  end

  M.log("Niveles activos: " .. table.concat(levels_shown, ", "), vim.log.levels.INFO)
end

-- Inicialización silenciosa - solo escribe al archivo de log
local function silent_init_log()
  local log_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(log_dir, "p")
  local log_file = log_dir .. "/copilot_log.txt"

  local file = io.open(log_file, "a")
  if file then
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local msg = "Log module initialized with level: " .. M.level_names[get_log_level()]
    file:write(timestamp .. " [CopilotChatAssist][INFO] " .. msg .. "\n")
    file:close()
  end
end

-- Inicializar silenciosamente
silent_init_log()

return M