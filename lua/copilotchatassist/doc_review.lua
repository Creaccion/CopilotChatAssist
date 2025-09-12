--[[
doc_review.lua

This module provides logic to review existing Markdown documentation and suggest improvements.
]]

local M = {}

-- Returns a prompt to review and suggest updates for a Markdown file
function M.review_markdown_prompt(filepath)
  return string.format(
    "Review the Markdown documentation in '%s'. Suggest improvements for clarity, completeness, formatting, and alignment with project best practices. If sections are outdated or missing, propose updates or additions.",
    filepath
  )
end

-- Example usage:
-- local prompt = M.review_markdown_prompt("/path/to/README.md")
-- Pass this prompt to your documentation assistant or LLM.

return M

