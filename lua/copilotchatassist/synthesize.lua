-- Module to synthesize project context
local log = require("copilotchatassist.utils.log")
local context_prompts = require("copilotchatassist.prompts.context")
local copilot_api = require("copilotchatassist.copilotchat_api")
local context = require("copilotchatassist.context")

local M = {}

-- Synthesize project context and save to file using asynchronous operations
function M.synthesize()
  -- Iniciar un indicador de progreso
  local progress = require("copilotchatassist.utils.progress")
  local spinner_id = "synthesize_project"
  local options = require("copilotchatassist.options")

  progress.start_spinner(spinner_id, "Generating project synthesis...", {
    style = options.get().progress_indicator_style,
    position = "statusline"
  })

  log.info({
    english = "Generating project synthesis...",
    spanish = "Generando síntesis del proyecto..."
  })

  local prompt = context_prompts.synthesis

  -- Configurar un timeout para evitar procesamiento infinito
  local timeout_timer = vim.loop.new_timer()
  timeout_timer:start(120000, 0, vim.schedule_wrap(function()
    -- Si después de 2 minutos aún está procesando, cancelar
    log.debug("Verificando si el proceso de síntesis sigue en curso...")

    -- Detener el spinner con error
    progress.stop_spinner(spinner_id, false)
    vim.notify("Timeout al generar síntesis. La operación tomó demasiado tiempo.", vim.log.levels.ERROR)

    -- Limpiar el timer
    timeout_timer:stop()
    timeout_timer:close()
  end))

  copilot_api.ask(prompt, {
    callback = function(response)
      -- Cancelar el timer de timeout ya que llegó la respuesta
      if timeout_timer then
        timeout_timer:stop()
        timeout_timer:close()
      end

      if response and response ~= "" then
        -- Procesar la respuesta de manera asíncrona para evitar bloqueos
        vim.schedule(function()
          -- Save synthesis to file
          local paths = context.get_context_paths()
          local synthesis_path = paths.synthesis

          -- Actualizar el progreso
          progress.update_spinner(spinner_id, "Saving project synthesis...")

          -- Guardar el archivo de forma no bloqueante usando vim.loop
          vim.loop.fs_open(synthesis_path, "w", 438, function(err, fd)
            if err then
              progress.stop_spinner(spinner_id, false)
              log.error({
                english = "Failed to open file for saving project synthesis: " .. err,
                spanish = "Error al abrir archivo para guardar la síntesis del proyecto: " .. err
              })
              return
            end

            vim.loop.fs_write(fd, response, 0, function(write_err)
              if write_err then
                progress.stop_spinner(spinner_id, false)
                log.error({
                  english = "Failed to write project synthesis: " .. write_err,
                  spanish = "Error al escribir la síntesis del proyecto: " .. write_err
                })
                vim.loop.fs_close(fd)
                return
              end

              vim.loop.fs_close(fd, function(close_err)
                if close_err then
                  log.warn({
                    english = "Warning when closing synthesis file: " .. close_err,
                    spanish = "Advertencia al cerrar archivo de síntesis: " .. close_err
                  })
                end

                -- Mostrar éxito en la UI principal de forma segura
                vim.schedule(function()
                  progress.stop_spinner(spinner_id, true)
                  log.info({
                    english = "Project synthesis saved to " .. synthesis_path,
                    spanish = "Síntesis del proyecto guardada en " .. synthesis_path
                  })

                  -- Mostrar un spinner final de éxito
                  local complete_spinner_id = "synthesis_complete"
                  progress.start_spinner(complete_spinner_id, "Project synthesis completed", {
                    style = options.get().progress_indicator_style,
                    position = "statusline"
                  })

                  -- Detener el spinner después de 2 segundos
                  vim.defer_fn(function()
                    progress.stop_spinner(complete_spinner_id, true)
                  end, 2000)
                end)
              end)
            end)
          end)
        end)
      else
        -- Detener el spinner con error
        progress.stop_spinner(spinner_id, false)
        log.error({
          english = "Failed to generate project synthesis",
          spanish = "Error al generar la síntesis del proyecto"
        })
      end
    end
  })
end

return M