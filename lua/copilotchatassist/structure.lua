local log = require("copilotchatassist.utils.log")

-- Example structure function
local function structure_action(msg)
  log.log("Structure: " .. msg)
end

return {
  structure_action = structure_action,
}
--
-- local M = {}
-- local context = require('copilotchatassist.context')
-- local hooks = require('copilotchatassist.hooks')
--
-- function M.generate_structure_for_requirement()
--
--     local ticket = context.extract_ticket_name()
--     print(ticket)
--     local requirement = context.get_or_ask_requirement(ticket)
--
--   print(requirement)
-- while not requirement or requirement == "" do
--   requirement = vim.fn.input("Requirement: ")
--   if not requirement or requirement == "" then
--     print("Requirement is required.")
--   end
-- end
--     -- 1. Check if structure exists in context (implement your own context logic)
--     local structure = M.get_structure_from_context(requirement)
--     if not structure then
--       -- 2. Ask CopilotChat for a proposal
--       local prompt = "Propon una estructura de archivos para el requerimiento: " .. requirement ..
--         ". Usa bloques de código con path y contenido/documentación inicial."
--         require('CopilotChat').ask(prompt, {
--           on_response = function(response)
--             hooks.apply_code_blocks_from_string(response)
--           end
--         })
--     else
--       hooks.apply_code_blocks_from_string(structure)
--     end
-- end
--
-- -- Dummy context checker (replace with your own logic)
-- function M.get_structure_from_context(requirement)
--   -- Example: return nil to always ask CopilotChat
--   return nil
-- end
--
-- return M
--
--
--
--
