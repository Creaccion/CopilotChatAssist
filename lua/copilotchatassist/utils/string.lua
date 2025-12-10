-- Utility module for string manipulation

local M = {}

-- Trim whitespace from both ends of a string
function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- Truncate a string to a maximum length, adding ellipsis if needed
function M.truncate_string(s, max_length)
  if not s then return "" end
  if not max_length or max_length <= 0 then return s end

  if #s <= max_length then
    return s
  else
    return string.sub(s, 1, max_length - 3) .. "..."
  end
end

return M
