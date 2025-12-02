local M = {}

local uv = vim.loop
local file_utils = require("copilotchatassist.utils.file")
local context = require("copilotchatassist.context")
local options = require("copilotchatassist.options")
local utils = require("copilotchatassist.utils")
local log = require("copilotchatassist.utils.log")
local copilot_api = require("copilotchatassist.copilotchat_api")
local paths = context.get_context_paths()

local api = vim.api
local status_icons = {
  ["DONE"] = "✅",
  ["TODO"] = "⬜",
  ["PENDING"] = "⬜",
  ["IN_PROGRESS"] = "",
  ["IN PROGRESS"] = "",
  ["✅ DONE"] = "✅",
  ["⬜ PENDING"] = "⬜",
  ["⬜ TODO"] = "⬜",
  ["✅"] = "✅",
  ["⬜"] = "⬜",
}

-- Load global options


local function parse_todo_markdown(path)
  local tasks = {}
  local lines = {}
  local f = io.open(path, "r")
  if not f then return tasks end
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  -- Find table header
  local header_idx = nil
  for i, line in ipairs(lines) do
    if line:match("|") and line:lower():find("status") then
      header_idx = i
      break
    end
  end
  if not header_idx then return tasks end
  -- Parse rows
  for i = header_idx + 2, #lines do
    local row = lines[i]
    if not row:match("|") or row:match("^%s*<!--") then break end
    local cols = {}
    for col in row:gmatch("|([^|]*)") do
      table.insert(cols, vim.trim(col))
    end
    if #cols >= 5 then
      table.insert(tasks, {
        number = cols[1],
        status = cols[2],
        priority = cols[3],
        category = cols[4],
        title = cols[5],
        description = cols[6] or "",
        raw = row,
      })
    end
  end
  return tasks
end

local function find_existing_todo_win()
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    local name = api.nvim_buf_get_name(buf)
    if name:find("TODO_") then
      return win, buf
    end
  end
  return nil, nil
end

local function extract_todo_title(lines)
  for _, line in ipairs(lines) do
    local title = line:match("^#%s*(TODO.*)")
    if title then
      return title
    end
  end
  return "TODO"
end

local function show_task_details(task)
  local lines = {
    "Task Details",
    "",
    "Number:      " .. (task.number or ""),
    "Status:      " .. (task.status or ""),
    "Priority:    " .. (task.priority or ""),
    "Category:    " .. (task.category or ""),
    "Title:       " .. (task.title or ""),
    "",
    "Description:",
    (task.description or ""),
  }
  local width = 60
  local height = #lines + 2
  local popup_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
  }
  local popup_win = api.nvim_open_win(popup_buf, true, opts)
  api.nvim_buf_set_option(popup_buf, "modifiable", false)
  api.nvim_buf_set_option(popup_buf, "buftype", "nofile")
  api.nvim_buf_set_keymap(popup_buf, "n", "<Esc>", "<cmd>bd!<CR>", { noremap = true, silent = true })
end
-- Helper: extract icon from status (first emoji or symbol)
local function extract_icon(status)
  -- Try to extract emoji/icon from status string
  local icon = status:match("[%z\1-\127\194-\244][\128-\191]*")
  if icon and (icon == "✅" or icon == "⬜" or icon == "") then
    return icon
  end
  -- If no emoji, map text to icon
  return status_icons[status] or status
end

-- Refresh/reload the TODO split
local function reload_todo_split(bufnr)
  local todo_path = paths.todo_path
  local tasks = parse_todo_markdown(todo_path)
  local display_lines = {}
  for _, task in ipairs(tasks) do
    local icon = extract_icon(task.status)
    table.insert(display_lines, string.format("%-3s %s", icon, task.title))
  end
  -- Add blank line and legend at the bottom
  table.insert(display_lines, "")
  table.insert(display_lines, "[Enter] Show details  |  [r] Refresh  |  [Esc] Close popup")
  api.nvim_buf_set_option(bufnr, "modifiable", true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, display_lines)
  api.nvim_buf_set_option(bufnr, "modifiable", false)
end

-- Main: open or reuse split for TODOs
function M.open_todo_split()
  local todo_path = paths.todo_path
  -- Try to find existing buffer/window for this TODO
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    if api.nvim_buf_get_name(buf) == todo_path then
      api.nvim_set_current_win(win)
      reload_todo_split(buf)
      return
    end
  end
  -- Open split (vertical by default)
  local orientation = options.todo_split_orientation or "vertical"
  if orientation == "vertical" then
    vim.cmd("vsplit")
  else
    vim.cmd("split")
  end
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(0, bufnr)
  api.nvim_buf_set_name(bufnr, todo_path)
  reload_todo_split(bufnr)
  api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  api.nvim_buf_set_option(bufnr, "swapfile", false)
  api.nvim_buf_set_option(bufnr, "modifiable", false)
  api.nvim_buf_set_option(bufnr, "readonly", true)
  -- Keymaps
  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    callback = function()
      local lnum = api.nvim_win_get_cursor(0)[1]
      local tasks = parse_todo_markdown(todo_path)
      if lnum > 0 and lnum <= #tasks then
        show_task_details(tasks[lnum])
      end
    end,
    desc = "Show task details",
  })
  api.nvim_buf_set_keymap(bufnr, "n", "r", "", {
    noremap = true,
    callback = function()
      vim.notify("Refreshig TODO " .. paths.todo_path, vim.log.levels.INFO)
      require("copilotchatassist.todos").generate_todo(function()
        reload_todo_split(bufnr)
      end)
    end,
    desc = "Refresh TODO list",
  })
end

function M.show_selected_task_details()
  local buf = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local title = extract_todo_title(lines)
  -- tasks start at line 3 (after title and blank)
  local tasks = {}
  for i = 3, #lines - 3 do
    local line = lines[i]
    if line and line:match("%S") then
      table.insert(tasks, line)
    end
  end
  local idx = line_nr - 2
  if idx < 1 or idx > #tasks then return end

  -- Reparse original file to get full details
  local todo_path = paths.todo_path
  local orig_lines = {}
  if todo_path and vim.fn.filereadable(todo_path) == 1 then
    orig_lines = vim.fn.readfile(todo_path)
  end
  local orig_tasks = parse_todo_markdown(orig_lines)
  local task = orig_tasks[idx]
  if task then
    show_task_details(task)
  end
end

-- Main: Generate TODO file from context
function M.generate_todo()
  -- Read requirement content
  local requirement = file_utils.read_file(paths.requirement) or ""
  local ticket_synthesis = file_utils.read_file(paths.synthesis) or ""
  local project_synthesis = file_utils.read_file(paths.project_context) or ""
  local todo = file_utils.read_file(paths.todo_path) or ""
  local full_context = requirement .. "\n" .. ticket_synthesis .. "\n" .. project_synthesis

  local prompt = require("copilotchatassist.prompts.todo_requests").default(full_context, ticket_synthesis, todo)
  vim.notify("Starting to refresh TODO ... ", vim.log.levels.INFO)
  copilot_api.ask(prompt, {
    headless = true,
    callback = function(response)
      file_utils.write_file(paths.todo_path, response or "")
      vim.notify("Project Requirement TODO saved: " .. paths.todo_path, vim.log.levels.INFO)
    end
  })
end

return M
