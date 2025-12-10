-- Prompt for synthesizing project context
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Always using language ]] .. options.language .. [[ for our interaction, and language ]] .. options.code_language .. [[ for everything related to code, documentation, debugging.
Synthesize the current project context in a self-contained and reusable way. Use only the available information, without introductions or farewells, and don't leave pending tasks.

Include:
- Main technology stack
- Key dependencies
- General project structure (summary of relevant files)
- Recent changes in the current branch compared to main
- Areas for improvement and specific recommendations
- Good practices applied or suggested

At the end, provide a high-level summary of the detected context. Choose the most appropriate format according to the project type: it can be an ASCII diagram, a DOT graph, or a list of main topics. This summary should be clear and serve as an introduction for future chat sessions.

Relevant files: #glob:**/*
Recent changes compared to main: #gitdiff:main..HEAD
]]

return M

