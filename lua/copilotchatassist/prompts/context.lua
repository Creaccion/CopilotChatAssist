-- Consolidated context prompts module
local options = require("copilotchatassist.options")

-- Create a modular approach to context prompts
local M = {}

-- Common headers and components for reuse
local function language_header()
  return "Always using language " .. options.language .. " for our interaction, and language " .. options.code_language .. " for everything related to code, documentation, debugging."
end

local function git_diff_component(branch)
  branch = branch or "main"
  return "Recent changes compared to " .. branch .. ": #gitdiff:" .. branch .. "..HEAD"
end

local function files_component()
  return "Relevant files: #glob:**/*"
end

-- Comprehensive project synthesis prompt (previously synthetize.lua)
M.synthesis = [[
]] .. language_header() .. [[

Create a comprehensive synthesis of the current project context in a self-contained and reusable way. Use only the available information, without introductions or farewells, and focus on providing a complete understanding of the project.

You must include detailed analysis of:

1. Technical Foundation:
   - Main technology stack with versions if detectable
   - Key dependencies and their roles in the project architecture
   - Build systems, test frameworks, and deployment tools
   - Language-specific patterns and paradigms being used

2. Project Architecture:
   - Overall architectural approach (MVC, microservices, etc.)
   - Module structure and organization principle
   - Directory organization and naming conventions
   - Interface boundaries and integration patterns

3. Codebase Analysis:
   - Critical components and their relationships
   - Core abstractions and domain model
   - State management approach
   - Error handling patterns
   - Performance optimization strategies

4. Development Workflow:
   - Branch management and git workflow patterns
   - CI/CD pipeline structure if detectable
   - Testing strategy and coverage approach
   - Code quality tools and enforcement mechanisms

5. Recent Evolution:
   - Recent changes in the current branch compared to main
   - Refactoring patterns observed
   - Feature development progression
   - Bug fixes and their implications

6. Quality Assessment:
   - Areas for improvement with specific, actionable recommendations
   - Technical debt hotspots with remediation suggestions
   - Good practices already applied
   - Opportunities for optimization or modernization

7. High-Level Summary:
   - Create a visual representation of the project structure
   - Choose the most appropriate format (ASCII diagram, DOT graph, or hierarchical list)
   - Highlight key dependencies and dataflow
   - Make the diagram clear enough to serve as an introduction for future sessions

Be specific rather than general. Include concrete examples from the code rather than vague descriptions. Focus on the unique aspects of this project rather than generic software development principles. Ensure your synthesis provides actionable insights that would help someone quickly understand and contribute to the project.

]] .. files_component() .. [[
]] .. git_diff_component()

-- Project context analysis prompt (previously project_context.lua)
M.project = [[
]] .. language_header() .. [[

You are an expert software architect and code reviewer.

Your task is to analyze the current state of the project using all available context, including the content of changed files, provided diffs, and, if possible, the full content of relevant files. Synthesize a clear summary of the project's current status, the progress made, and the definitions established during this session.

Explicitly identify and summarize the changes provided in the diffs. Highlight key technologies, architecture, dependencies, and any significant improvements or refactoring. List areas of progress, pending tasks, and actionable recommendations for further development.

Include any elements or context that will be relevant for continuing work in future sessions, ensuring there is no ambiguity for future contributors. Do not ask questions or request additional information. Only deliver a factual, actionable summary and recommendations.
]]

-- Global project context analysis prompt (previously global_context.lua)
M.global = [[
]] .. language_header() .. [[

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

-- Context update check prompt (previously context_update.lua)
M.update = [[
]] .. language_header() .. [[

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

-- Ticket synthesis prompt (previously ticket_synthesis.lua)
M.ticket_synthesis = [[
]] .. language_header() .. [[

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

-- Function to build customized prompts
M.build = function(base_prompt, replacements)
  local result = base_prompt

  if replacements then
    for key, value in pairs(replacements) do
      result = result:gsub("<" .. key .. ">", value)
    end
  end

  return result
end

return M