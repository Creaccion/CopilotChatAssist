
local log = require("copilotchatassist.utils.log")

-- Example synthesize function
local function synthesize_action(msg)
  log.log("Synthesize: " .. msg)
end

return {
  synthesize_action = synthesize_action,
}
-- local utils = require("copilotchatassist.utils")
-- local CopilotChat = require("CopilotChat") -- Import required module
-- -- Synthesis and save logic for CopilotChat
-- local M = {}
-- function M.synthesize_and_save_api()
--   local project_name = utils.get_project_name() -- Correct usage
--   local context_dir = utils.get_context_dir() -- Correct usage
--   local prompt = [[
--     Sintetiza el contexto actual del proyecto de forma autocontenida y reutilizable. Usa solo la información disponible, sin introducciones ni despedidas, y no dejes tareas pendientes.
--
--     Incluye:
--     - Stack tecnológico principal
--     - Dependencias clave
--     - Estructura general del proyecto (resumen de archivos relevante)
--     - Cambios recientes en el branch actual respecto a main
--     - Áreas de mejora y recomendaciones concretas
--     - Buenas prácticas aplicadas o sugeridas
--
--     Al final, proporciona un resumen de alto nivel del contexto detectado. Elige el formato más adecuado según el tipo de proyecto: puede ser un diagrama ASCII, un gráfico DOT, o una lista de temas principales. Este resumen debe ser claro y servir como introducción para futuras sesiones de chat.
--
--     Archivos relevantes: #glob:**/*
--     Cambios recientes respecto a main: #gitdiff:main..HEAD
--   ]]
--   CopilotChat.ask(prompt, {
--     headless = true,
--     callback = function(response)
--       vim.fn.mkdir(context_dir, "p")
--       local context_path = context_dir .. project_name .. "_synthesis.md"
--       local text = response.content or response.data or tostring(response)
--
--       -- Save asynchronously using a shell command
--       local cmd = string.format("echo '%s' > '%s'", text:gsub("'", "'\\''"), context_path)
--       local handle
--       handle = vim.loop.spawn("sh", {
--         args = {"-c", cmd},
--         detached = true,
--       }, function(code, signal)
--         if code == 0 then
--           vim.schedule(function()
--             vim.notify("CopilotChat synthesis saved asynchronously in: " .. context_path, vim.log.levels.INFO)
--           end)
--         else
--           vim.schedule(function()
--             vim.notify("Error saving CopilotChat synthesis asynchronously.", vim.log.levels.ERROR)
--           end)
--         end
--         handle:close()
--       end)
--     end
--   })
-- end
--
-- function M.on_buf_leave(args)
--     local buf = args.buf
--     if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
--     vim.ui.select(
--       { "Sí", "No" },
--       { prompt = "¿Deseas sintetizar y guardar el contexto de CopilotChat?" },
--       function(choice)
--         if choice == "Sí" then
--           M.synthesize_and_save_api()
--         end
--       end
--     )
--   end
--
-- return M
