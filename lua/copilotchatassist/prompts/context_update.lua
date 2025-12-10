local M = {}
local options = require("copilotchatassist.options")

M.default = [[
Siempre usando el lenguage ]] .. options.language .. [[ para nuestra interaccion, y el lenguaje ]] .. options.code_language .. [[ para todo lo relacionado al código, documentacion, debugs. 
You are an expert assistant for project and ticket context management.

Given the following requirement and the currently persisted context, analyze if the context stored in the file is outdated or incomplete based on the requirement.

- If the context should be updated to reflect new information, changes, or improvements, answer only "yes".
- If the context is already up-to-date and complete, answer only "no".
- Do not include explanations, just reply "yes" or "no".

Requirement:
<requirement>

Current persisted context:
<context>
]]

return M

