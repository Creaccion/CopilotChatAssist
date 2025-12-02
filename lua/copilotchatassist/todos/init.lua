local M = {}

local uv = vim.loop
local file_utils = require("copilotchatassist.utils.file")
local context = require("copilotchatassist.context")
local options = require("copilotchatassist.options")
local utils = require("copilotchatassist.utils")
local log = require("copilotchatassist.utils.log")
local copilot_api = require("copilotchatassist.copilotchat_api")
local api = vim.api

-- Load global options
local options = require("copilotchatassist.options")
local context = require("copilotchatassist.context")

-- Default config
local config = {
  orientation = options.todo_split_orientation or "vertical", -- "vertical" or "horizontal"
  mode = options.todo_split_mode or "readonly", -- "readonly" or "edit"
}

--- Set TODO split configuration
-- @param opts table { orientation = "vertical"|"horizontal", mode = "readonly"|"edit" }
function M.set_config(opts)
  config.orientation = opts.orientation or config.orientation
  config.mode = opts.mode or config.mode
end

--- Find an existing TODO window, returns window id or nil
local function find_todo_win(todo_path)
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    local name = api.nvim_buf_get_name(buf)
    if name == todo_path then
      return win
    end
  end
  return nil
end

--- Open TODO split for current context
function M.open_todo_split()
  local paths = context.get_context_paths()
  local todo_path = paths and paths.todo_path
  if not todo_path or todo_path == "" then
    vim.notify("No TODO file found for current context.", vim.log.levels.WARN)
    return
  end

  local win = find_todo_win(todo_path)
  if win and api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
    return
  end

  if config.orientation == "vertical" then
    vim.cmd("vsplit " .. vim.fn.fnameescape(todo_path))
  else
    vim.cmd("split " .. vim.fn.fnameescape(todo_path))
  end

  local buf = api.nvim_get_current_buf()
  if config.mode == "readonly" then
    api.nvim_buf_set_option(buf, "modifiable", false)
    api.nvim_buf_set_option(buf, "readonly", true)
  else
    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_option(buf, "readonly", false)
  end
end



-- Main: Generate TODO file from context
function M.generate_todo()
  local paths = context.get_context_paths()
  -- Read requirement content
  local requirement = file_utils.read_file(paths.requirement) or ""
  local ticket_synthesis = file_utils.read_file(paths.synthesis) or ""
  local project_synthesis = file_utils.read_file(paths.project_context) or ""
  local todo = file_utils.read_file(paths.todo_path) or ""
  local full_context = requirement .. "\n" .. ticket_synthesis .. "\n" .. project_synthesis

  local prompt = require("copilotchatassist.prompts.todo_requests").default(full_context, todo)
  copilot_api.ask(prompt,{
    headless = true,
    callback = function(response)
      file_utils.write_file(paths.todo_path, response or "")
      vim.notify("Project Requeriment TODO saved: " .. paths.todo_path, vim.log.levels.INFO)
    end
  })
end

return M

