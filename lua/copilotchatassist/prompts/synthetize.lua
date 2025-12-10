-- Prompt for synthesizing project context
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Always using language ]] .. options.language .. [[ for our interaction, and language ]] .. options.code_language .. [[ for everything related to code, documentation, debugging.
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

Relevant files: #glob:**/*
Recent changes compared to main: #gitdiff:main..HEAD
]]

return M

