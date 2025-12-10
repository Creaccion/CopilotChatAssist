-- Prompt for enriching ticket synthesis
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Always using language ]] .. options.language .. [[ for our interaction, and language ]] .. options.code_language .. [[ for everything related to code, documentation, debugging.
Enrich the ticket synthesis by adding:

- Pending tasks, numbered and with checks
- Problems to solve, with brief description
- Updated context according to recent changes
- Recommendations to progress and close the ticket

Keep the information organized and ready to update the ticket context.
Do not include introductions or farewells.
]]

return M

