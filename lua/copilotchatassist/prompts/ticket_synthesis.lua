-- Prompt for ticket synthesis
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Always using language ]] .. options.language .. [[ for our interaction, and language ]] .. options.code_language .. [[ for everything related to code, documentation, debugging.
Synthesize the current ticket context including:

- Main technology stack and relevant dependencies
- Changes made in the branch with respect to main
- Associated requirement and Jira link (if applicable)
- List of pending tasks and progress
- Areas for improvement and specific recommendations for the ticket
- Detected problems and solution suggestions

Present the information in a clear and structured manner, ready to be reused in future sessions.
Respond exclusively in the configured language unless the user explicitly requests another language.
]]

return M

