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
  ["✅ DONE"] = "✅",
  ["DONE"] = "✅",
  ["PENDING"] = "⬜",
  ["⬜ PENDING"] = "⬜",
  ["⬜ TODO"] = "⬜",
  ["IN_PROGRESS"] = "",
  ["✅"] = "✅",
  ["⬜"] = "⬜",
}

-- Load global options


local function parse_markdown_table(lines)
  local tasks = {}
  for _, line in ipairs(lines) do
    if line:match("^|") and not line:match("^|%s*-") then
      local cols = {}
      for col in line:gmatch("|([^|]+)") do
        table.insert(cols, vim.trim(col))
      end
      if #cols >= 6 and cols[1] ~= "#" then
        table.insert(tasks, {
          number = cols[1],
          status = cols[2],
          priority = cols[3],
          category = cols[4],
          title = cols[5],
          description = cols[6],
        })
      end
    end
  end
  return tasks
end

local function get_todo_path()
  local context = require("copilotchatassist.context")
  local paths = context.get_context_paths()
  return paths and paths.todo_path or nil
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

function M.open_todo_split()
  local todo_path = get_todo_path()
  if not todo_path or vim.fn.filereadable(todo_path) == 0 then
    vim.notify("TODO file not found: " .. tostring(todo_path), vim.log.levels.ERROR)
    return
  end

  local win, buf = find_existing_todo_win()
  if win and api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
  else
    vim.cmd("vsplit " .. vim.fn.fnameescape(todo_path))
    win = api.nvim_get_current_win()
    buf = api.nvim_get_current_buf()
  end

  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_option(buf, "readonly", true)
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "filetype", "markdown")

  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local title = extract_todo_title(lines)
  local tasks = parse_markdown_table(lines)

  local display_lines = {}
  table.insert(display_lines, "# " .. title)
  table.insert(display_lines, "")
  for _, task in ipairs(tasks) do
    local icon = status_icons[task.status] or task.status
    table.insert(display_lines, string.format("%-6s %s", icon, task.title))
  end
  table.insert(display_lines, "")
  table.insert(display_lines, "[Enter] Show details  |  [Esc] Close popup")

  api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  api.nvim_buf_set_option(buf, "modifiable", false)

  -- Map <CR> to show details
  api.nvim_buf_set_keymap(buf, "n", "<CR>",
    [[<cmd>lua require('copilotchatassist.todos').show_selected_task_details()<CR>]], { noremap = true, silent = true })
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
  local todo_path = get_todo_path()
  local orig_lines = {}
  if todo_path and vim.fn.filereadable(todo_path) == 1 then
    orig_lines = vim.fn.readfile(todo_path)
  end
  local orig_tasks = parse_markdown_table(orig_lines)
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

  local prompt = require("copilotchatassist.prompts.todo_requests").default(full_context, todo)
  copilot_api.ask(prompt, {
    headless = true,
    callback = function(response)
      file_utils.write_file(paths.todo_path, response or "")
      vim.notify("Project Requeriment TODO saved: " .. paths.todo_path, vim.log.levels.INFO)
    end
  })
end

return M
