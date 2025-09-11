-- Utility module for file and directory operations

local M = {}

-- Write content to a file at the given path
function M.write_file(path, content)
  local file = io.open(path, "w")
  if file then
    if type(content) == "table" then
      if content.content then
        content = content.content
      else
        content = vim.inspect(content)
      end
    end
    file:write(content)
    file:close()
    return true
  else
    return false
  end
end

-- Read content from a file
function M.read_file(path)
  local file = io.open(path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    return content
  end
  return nil
end

-- Create a directory if it does not exist
function M.ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

return M
