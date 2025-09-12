--[[
prompts/doc_changes.lua

This module provides the main prompt logic for documentation generation and Markdown file suggestions,
using the enhanced logic from doc_changes.lua.
]]

local doc_changes = require("copilotchatassist.doc_changes")

local M = {}

-- Returns a prompt for documentation changes and missing Markdown files
-- filetype: string (e.g., "lua", "python", "markdown")
-- filepath: string (absolute path to the file)
-- project_root: string (absolute path to the project root)
function M.get_doc_prompt(filetype, filepath, project_root)
  return doc_changes.suggest_doc_changes(filetype, filepath, project_root)
end
-- Example usage:
-- local prompt = require("copilotchatassist.prompts.doc_changes").get_doc_prompt("lua", "/path/to/file.lua", "/path/to/project/root")
-- Pass 'prompt' to your documentation assistant or LLM.

return M
