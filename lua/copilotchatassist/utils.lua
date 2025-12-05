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

return M
