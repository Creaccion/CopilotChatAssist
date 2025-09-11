-- Prompt for documenting code changes

local M = {}

M.default = [[
For the following changes in <file>:
- Use the standard documentation comment format for this language.
- Place the documentation immediately above the class, method, or function definition (never above the package statement).
- Do not include any code, file paths, or markdown code blocks.
- Return only the documentation comments, nothing else.
<diff>
]]

return M

