-- Prompt for global project context analysis
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Always using language ]] .. options.language .. [[ for our interaction, and language ]] .. options.code_language .. [[ for everything related to code, documentation, debugging.
Analyze the project by automatically detecting the main technology stack based on the files present: ##files://glob/**.*

- If you detect more than one stack, ask which one should be used.
- Include patterns of relevant files, infrastructure files, and containers if they exist.
- Analyze all Markdown documentation files (*.md) ##files://glob/**.md and use their content to enrich the context and analysis.
- If you need more information, request the project structure or access to specific files.

Provide:
- Summary of the project purpose
- General structure and component organization
- Areas for improvement in architecture, code, and best practices
- Dependency analysis and recommendations
- Suggestions for documentation and context
- CI/CD recommendations (for example: Buildkite, CircleCI)
- Security and performance best practices
- Other relevant aspects

Keep this context for future consultations.
Important, this result will not interact with the user, so do not ask questions, instead add points in the result
to be addressed with the user when the time comes.
]]

return M

