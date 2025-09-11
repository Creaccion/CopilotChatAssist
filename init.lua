local utils = require("copilotchatassist.utils")
local log = require("copilotchatassist.utils.log")
local options = require("copilotchatassist.options")
local context = require("copilotchatassist.context")
local pr_generator = require("copilotchatassist.pr_generator")

local M = {}

function M.setup(user_opts)
  options.set(user_opts or {})
  local copilotchat_opts = options.get_copilotchat_config()
  require("CopilotChat").setup(copilotchat_opts)
end

vim.api.nvim_create_user_command(
  "CopilotTickets",
  function() context.copilot_tickets() end,
  { desc = "Open or create context for current ticket/branch" }
)

vim.api.nvim_create_user_command(
  "CopilotEnhancePR",
  function() pr_generator.improve_pr_description() end,
  { desc = "Generate or improve PR description" }
)

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
