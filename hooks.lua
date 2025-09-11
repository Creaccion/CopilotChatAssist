local file_utils = require("copilotchatassist.utils.file")
local log = require("copilotchatassist.utils.log")

-- Example hook using file and log utilities
local function on_save(path, content)
  file_utils.ensure_dir(vim.fn.fnamemodify(path, ":h"))
  if file_utils.write_file(path, content) then
    log.log("File saved: " .. path)
  else
    log.log("Failed to save file: " .. path, vim.log.levels.ERROR)
  end
end

return {
  on_save = on_save,
}
