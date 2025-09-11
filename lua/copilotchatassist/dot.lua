local utils = require("copilotchatassist.utils")
local file_utils = require("copilotchatassist.utils.file")
local log = require("copilotchatassist.utils.log")

-- Example usage of visual selection and file utilities
local function process_visual_selection()
  local selection = utils.get_visual_selection()
  if selection == "" then
    log.log("No visual selection found.", vim.log.levels.WARN)
    return
  end
  local path = "/tmp/selection.txt"
  file_utils.write_file(path, selection)
  log.log("Selection written to " .. path)
end

return {
  process_visual_selection = process_visual_selection,
}
