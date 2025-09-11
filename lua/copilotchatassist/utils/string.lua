-- Utility module for string manipulation

local M = {}

-- Trim whitespace from both ends of a string
function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

return M
