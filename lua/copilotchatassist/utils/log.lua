-- Módulo de log simplificado para CopilotChatAssist
local M = {}

-- Niveles de log para compatibilidad
M.levels = {
  ERROR = vim.log.levels.ERROR,
  WARN = vim.log.levels.WARN,
  INFO = vim.log.levels.INFO,
  DEBUG = vim.log.levels.DEBUG,
  TRACE = vim.log.levels.TRACE
}

-- Función de log genérica
function M.log(msg, level)
  level = level or vim.log.levels.INFO

  -- Convertir objetos no string a string
  if type(msg) ~= "string" then
    msg = vim.inspect(msg)
  end

  -- Prefijo para todos los mensajes
  local prefix = "[CopilotChatAssist] "

  -- Usar vim.notify directamente
  vim.notify(prefix .. msg, level)
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
  -- Para debug, podemos silenciarlo en producción
  -- o controlarlo con una variable global
  if vim.g.copilotchatassist_debug then
    M.log(msg, vim.log.levels.DEBUG)
  end
end

function M.trace(msg)
  -- Igual que debug, controlado por variable
  if vim.g.copilotchatassist_trace then
    M.log(msg, vim.log.levels.TRACE)
  end
end

return M