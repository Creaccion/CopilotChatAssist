local utils = require("copilotchatassist.utils")
local log = require("copilotchatassist.utils.log")
local options = require("copilotchatassist.options")
local context = require("copilotchatassist.context")
local pr_generator = require("copilotchatassist.pr_generator")

local todos = require("copilotchatassist.todos")
local M = {}

function M.setup(user_opts)
  options.set(user_opts or {})
end

function M.get_copilotchat_config()
  return options.get_copilotchat_config()
end

vim.api.nvim_create_user_command(
  "CopilotTickets",
  function() context.copilot_tickets() end,
  { desc = "Open or create context for current ticket/branch" }
)

vim.api.nvim_create_user_command(
  "CopilotEnhancePR",
  function() pr_generator.enhance_pr_description() end,
  { desc = "Generate or improve PR description" }
)


-- Register Neovim command to generate TODO from context and requirement
vim.api.nvim_create_user_command("CopilotGenerateTodo", function(opts)
  local context_path = opts.fargs[1]
  local requirement_path = opts.fargs[2]
  if context_path and requirement_path then
    todos.generate_todo(context_path, requirement_path)
    print("TODO file generated for context: " .. context_path)
  else
    print("Usage: CopilotGenerateTodo <context_path> <requirement_path>")
  end
end, { nargs = "2" })

-- Example integration: When generating context, also generate TODO
-- Replace this with your actual context generation logic
function GenerateContextAndTodo(context_path, requirement_path)
  -- ... your context generation logic here ...
  todos.generate_todo(context_path, requirement_path)
end
return M
-- local M = {}
-- local hooks = require('copilotchatassist.hooks')
-- M.agent_pr = require("copilotchatassist.agent_pr")
-- M.agent_doc = require("copilotchatassist.doc_changes")
-- M.structure = require("copilotchatassist.structure")
-- M.context = require("copilotchatassist.context")
--
-- vim.api.nvim_create_user_command(
--   'CopilotChatGenerateStructure', M.structure.generate_structure_for_requirement, {}
-- )
-- -- Agrega otros agentes si los tienes
--
-- return M
