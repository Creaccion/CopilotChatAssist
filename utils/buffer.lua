-- Utility module for buffer and window operations

local M = {}

-- Create a new split and open a buffer
function M.open_split_buffer(name, content)
  vim.cmd("vsplit")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
  vim.api.nvim_set_current_buf(buf)
end

return M
