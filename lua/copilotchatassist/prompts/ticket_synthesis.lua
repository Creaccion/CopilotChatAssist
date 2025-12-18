-- Prompt for ticket synthesis
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Always using language ]] .. (options.language or "english") .. [[ for our interaction, and language ]] .. (options.code_language or "lua") .. [[ for everything related to code, documentation, debugging.

Create a detailed synthesis of the current ticket context that provides a complete understanding of the work being done. Your analysis must include:

1. Technical Context:
   - Main technology stack and relevant dependencies specific to this ticket
   - Frameworks, libraries, and tools directly involved in the implementation
   - Technical constraints and requirements that shape the solution
   - Performance considerations and implications

2. Implementation Details:
   - Precise changes made in the branch with respect to main
   - Files modified and their functional purpose
   - Key algorithms or patterns introduced or modified
   - Data structures affected and how they've changed
   - Interface changes and their impact on other components

3. Requirements and Tracking:
   - Associated requirement and Jira link (if detectable)
   - Original acceptance criteria or requirements
   - Business value and user-facing impact of the changes
   - Priority level and release target (if detectable)

4. Progress Analysis:
   - Comprehensive list of completed tasks with completion evidence
   - Current in-progress tasks with status indicators
   - Pending tasks organized by dependency or complexity
   - Estimated percentage of completion with justification

5. Quality Assessment:
   - Code quality evaluation of implemented changes
   - Test coverage analysis and gaps
   - Areas for improvement with specific, actionable recommendations
   - Detected problems with concrete solution suggestions

6. Implementation Strategy:
   - Recommended next steps with specific code suggestions
   - Alternative approaches with pros and cons
   - Potential roadblocks with mitigation strategies
   - Integration considerations with other system components

For each section, include concrete examples from the code rather than vague descriptions. Reference specific files, functions, and line numbers where appropriate. Focus on actionable insights that would help someone continue working on the ticket effectively.

Present the information in a clear, structured, and visually organized manner, ready to be reused in future sessions. Use bullet points, tables, code snippets, and other formatting to improve readability.
]]

return M