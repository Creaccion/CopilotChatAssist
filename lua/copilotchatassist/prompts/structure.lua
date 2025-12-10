-- Prompt for proposing file structure
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Always using language ]] .. options.language .. [[ for our interaction, and language ]] .. options.code_language .. [[ for everything related to code, documentation, debugging.
Propose a file structure for the requirement: <requirement>.
Use code blocks with path and initial content/documentation.
]]

return M

