local options = require("copilotchatassist.options")
local M = {}

local level_map = {
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
  debug = vim.log.levels.DEBUG,
  trace = vim.log.levels.TRACE,
}

local function valid_level(level)
  if type(level) == "number" then
    return level
  elseif type(level) == "string" then
    return level_map[level:lower()] or vim.log.levels.INFO
  end
  return vim.log.levels.INFO
end

function M.log(msg, level)
  local config_level = valid_level(options.get().log_level)
  level = valid_level(level)
  if level >= config_level then
    vim.notify(msg, level)
  end
end

return M
