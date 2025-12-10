-- Prompt for enriching ticket synthesis
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Always using language ]] .. options.language .. [[ for our interaction, and language ]] .. options.code_language .. [[ for everything related to code, documentation, debugging.
Enrich the ticket synthesis with a comprehensive analysis that provides deeper insights and actionable next steps. Your enrichment must include:

1. Task Breakdown:
   - Detailed pending tasks with numbered steps and checkboxes
   - Tasks organized by priority and dependency order
   - Estimated effort level for each task (low, medium, high)
   - Technical skills required for each task
   - Potential blockers or prerequisites for each task

2. Problem Analysis:
   - Thorough analysis of problems to solve with technical root causes
   - Impact assessment of each problem on functionality and user experience
   - Edge cases and corner scenarios that need special handling
   - System limitations or constraints affecting the solution approach
   - Dependencies on external systems or components

3. Context Evolution:
   - Updated context based on recent code changes and commits
   - New patterns or architecture decisions that emerged
   - Changes in requirements or scope since ticket creation
   - Integration points affected by recent changes
   - New insights from related tickets or pull requests

4. Implementation Strategy:
   - Concrete recommendations with specific code examples
   - Design patterns appropriate for the solution
   - Performance optimization opportunities
   - Testing strategy with specific test cases
   - Documentation needs and update recommendations

5. Completion Path:
   - Clear definition of "done" for this ticket
   - Validation steps to ensure correctness
   - Review guidelines specific to this implementation
   - Deployment considerations and release planning
   - Post-implementation verification steps

For each section, include concrete examples and specific references to the codebase rather than abstract descriptions. Use formatting like tables, bullet points, and code blocks to improve clarity and readability.

Keep the information precisely organized and immediately actionable for developers continuing work on the ticket.
Do not include introductions or farewells.
]]

return M

