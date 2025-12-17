-- Module to synthesize project context
local log = require("copilotchatassist.utils.log")
local context_prompts = require("copilotchatassist.prompts.context")
local copilot_api = require("copilotchatassist.copilotchat_api")
local context = require("copilotchatassist.context")

local M = {}

-- Synthesize project context and save to file
function M.synthesize()
  log.info({
    english = "Generating project synthesis...",
    spanish = "Generando síntesis del proyecto..."
  })

  local prompt = context_prompts.synthesis

  copilot_api.ask(prompt, {
    callback = function(response)
      if response and response ~= "" then
        -- Save synthesis to file
        local paths = context.get_context_paths()
        local synthesis_path = paths.synthesis

        local file = io.open(synthesis_path, "w")
        if file then
          file:write(response)
          file:close()
          log.info({
            english = "Project synthesis saved to " .. synthesis_path,
            spanish = "Síntesis del proyecto guardada en " .. synthesis_path
          })
        else
          log.error({
            english = "Failed to save project synthesis",
            spanish = "Error al guardar la síntesis del proyecto"
          })
        end
      else
        log.error({
          english = "Failed to generate project synthesis",
          spanish = "Error al generar la síntesis del proyecto"
        })
      end
    end
  })
end

return M