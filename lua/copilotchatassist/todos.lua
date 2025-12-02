local M = {}

local uv = vim.loop
local languages = require("copilotchatassist.utils.language")

-- Main: Generate TODO file from context
function M.generate_todo(context_path, requirement_path)
  -- Read requirement content
  local requirement_content = ""
  local req_fd = uv.fs_open(requirement_path, "r", 438)
  if req_fd then
    local stat = uv.fs_fstat(req_fd)
    requirement_content = uv.fs_read(req_fd, stat.size, 0) or ""
    uv.fs_close(req_fd)
  end

  local language = languages.detect_language(context_path, requirement_content)
  local tasks = languages.extract_tasks(requirement_content)
  local bp_tasks = languages.best_practice_tasks(language)
  for _, t in ipairs(bp_tasks) do table.insert(tasks, t) end

  -- Compose TODO markdown
  local todo_lines = {}
  for _, t in ipairs(tasks) do
    table.insert(todo_lines, string.format("- [ ] [%s][%s] %s", t.section, t.priority, t.text))
  end

  -- Write TODO file
  local todo_path = context_path:gsub("_requirement%.txt$", "_todo.md")
  local fd = uv.fs_open(todo_path, "w", 438)
  if fd then
    uv.fs_write(fd, table.concat(todo_lines, "\n"))
    uv.fs_close(fd)
  end
end

-- Main: Sync TODO completion with context synthesis
function M.sync_todo_with_context(todo_path, synthesis_path)
  -- Read TODO file
  local todo_content = ""
  local fd = uv.fs_open(todo_path, "r", 438)
  if fd then
    local stat = uv.fs_fstat(fd)
    todo_content = uv.fs_read(fd, stat.size, 0) or ""
    uv.fs_close(fd)
  end

  -- Count completed tasks
  local completed, total = 0, 0
  for line in todo_content:gmatch("[^\r\n]+") do
    if line:match("%[x%]") then completed = completed + 1 end
    if line:match("%[ %]") or line:match("%[x%]") then total = total + 1 end
  end

  -- Update synthesis file with progress
  local synthesis_content = ""
  local sfd = uv.fs_open(synthesis_path, "r", 438)
  if sfd then
    local stat = uv.fs_fstat(sfd)
    synthesis_content = uv.fs_read(sfd, stat.size, 0) or ""
    uv.fs_close(sfd)
  end

  local progress_line = string.format("Progress: %d/%d tasks completed", completed, total)
  if synthesis_content:find("Progress:") then
    synthesis_content = synthesis_content:gsub("Progress:%s*%d+/%d+ tasks completed", progress_line)
  else
    synthesis_content = synthesis_content .. "\n" .. progress_line
  end

  local sfdw = uv.fs_open(synthesis_path, "w", 438)
  if sfdw then
    uv.fs_write(sfdw, synthesis_content)
    uv.fs_close(sfdw)
  end
end

-- Main: Update TODO/context from git diff
function M.update_from_diff(diff_output, todo_path, synthesis_path)
  -- Simple heuristic: If diff mentions a function/class/module, add a TODO for tests/documentation
  local new_tasks = {}
  for line in diff_output:gmatch("[^\r\n]+") do
    if line:match("^%+%s*function") or line:match("^%+%s*def") or line:match("^%+%s*class") or line:match("^%+%s*module") then
      table.insert(new_tasks, "- [ ] [Diff][P1] Add tests and documentation for new code: " .. line:gsub("^%+%s*", ""))
    end
  end
  if #new_tasks > 0 then
    -- Append to TODO file
    local fd = uv.fs_open(todo_path, "a", 438)
    if fd then
      uv.fs_write(fd, table.concat(new_tasks, "\n") .. "\n")
      uv.fs_close(fd)
    end
    -- Optionally, update synthesis file with new tasks summary
    local sfd = uv.fs_open(synthesis_path, "a", 438)
    if sfd then
      uv.fs_write(sfd, "\nNew tasks from diff:\n" .. table.concat(new_tasks, "\n"))
      uv.fs_close(sfd)
    end
  end
end

return M
