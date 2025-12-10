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

  return configured_level
end

-- Función para verificar si un nivel de log debe ser mostrado
-- @param level number: Nivel del mensaje de log
-- @return boolean: true si el mensaje debe ser mostrado, false en caso contrario
local function should_log(level)
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

  if level == vim.log.levels.DEBUG or level == vim.log.levels.TRACE then
    -- For debug and trace levels, just print to console instead of showing notifications
    print(prefix .. " " .. msg)
  else
    -- For ERROR, WARN, and INFO use notify
    vim.notify(prefix .. " " .. msg, level)
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
  M.log(msg, vim.log.levels.INFO)
end

function M.debug(msg)
  M.log(msg, vim.log.levels.DEBUG)
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

-- Inicialización
-- Inicializar con mensaje traducido (using INFO to ensure it's visible)
M.info({
  english = "Log module initialized with level: " .. M.level_names[get_log_level()],
  spanish = "Módulo de log inicializado with level: " .. M.level_names[get_log_level()]
})

return M