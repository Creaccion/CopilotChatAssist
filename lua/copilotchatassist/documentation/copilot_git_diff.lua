-- Módulo para integrar la funcionalidad #gitdiff de CopilotChat con la documentación
local M = {}
local log = require("copilotchatassist.utils.log")
local copilotchat_api = require("copilotchatassist.copilotchat_api")

-- Función para analizar los cambios de git utilizando CopilotChat
-- @param file_path string: Ruta del archivo a verificar
-- @param opts table: Opciones adicionales
-- @return table: Lista de rangos de líneas cambiados {start_line, end_line, type}
function M.get_changed_lines_via_copilot(file_path, opts)
  opts = opts or {}

  -- Determinar el rango de comparación
  local range = opts.range or "origin/main..HEAD"
  local command = "#gitdiff:" .. range

  log.debug("Solicitando diff a CopilotChat con comando: " .. command)

  -- Iniciar spinner de progreso
  local progress = require("copilotchatassist.utils.progress")
  local options = require("copilotchatassist.options")
  local spinner_id = "git_diff_copilot"
  progress.start_spinner(spinner_id, "Getting Git diff via CopilotChat", {
    style = options.get().progress_indicator_style,
    position = "statusline"
  })

  -- Almacenar los resultados
  local result = {}
  local promise = vim.defer_fn(function() return {} end, 0)

  -- Solicitar el diff a CopilotChat
  copilotchat_api.ask(command, {
    callback = function(response)
      if not response or response == "" then
        log.warn("CopilotChat devolvió una respuesta vacía para el comando git diff")
        return {}
      end

      -- Procesar la respuesta para extraer información de cambios
      log.debug("CopilotChat devolvió respuesta de " .. #response .. " bytes")

      -- Buscar líneas con formato @@ -a,b +c,d @@ donde c es línea de inicio y d es número de líneas
      for start_line, num_lines in string.gmatch(response, "@@ %-%d+,%d+ %+(%d+),(%d+) @@") do
        local start = tonumber(start_line)
        local count = tonumber(num_lines)
        if start and count and count > 0 then
          table.insert(result, {
            start_line = start,
            end_line = start + count - 1,
            type = "modified"
          })
        end
      end

      -- También incluir líneas individuales
      for line in string.gmatch(response, "@@ %-%d+,%d+ %+(%d+) @@") do
        local line_num = tonumber(line)
        if line_num then
          table.insert(result, {
            start_line = line_num,
            end_line = line_num,
            type = "modified"
          })
        end
      end

      log.debug("Se encontraron " .. #result .. " rangos de líneas modificados en la respuesta de CopilotChat")

      -- Detener spinner con éxito
      progress.stop_spinner(spinner_id, true)

      -- Mostrar resultado con spinner
      local complete_spinner_id = "git_diff_complete"
      progress.start_spinner(complete_spinner_id, "Found " .. #result .. " changed ranges", {
        style = options.get().progress_indicator_style,
        position = "statusline"
      })

      -- Detener el spinner después de 2 segundos
      vim.defer_fn(function()
        progress.stop_spinner(complete_spinner_id, true)
      end, 2000)
    end,
    prompt_prefix = "Muestra el diff completo para el archivo " .. file_path .. " en formato unificado:",
    system_prompt = "Actúa como una herramienta git diff. Solo muestra el diff en formato unificado para el archivo específico. No incluyas ningún comentario ni explicación.",
    sync = true
  })

  return result
end

-- Detecta elementos cambiados usando CopilotChat
-- @param buffer number: ID del buffer a analizar
-- @param opts table: Opciones adicionales
-- @return table: Lista de elementos detectados con información de cambios
function M.detect_changed_elements_via_copilot(buffer, opts)
  opts = opts or {}
  local file_path = vim.api.nvim_buf_get_name(buffer)

  -- Verificar que es un archivo válido
  if not file_path or file_path == "" then
    log.warn("No se pudo obtener la ruta del archivo para el buffer " .. buffer)
    return {}
  end

  -- Obtener los rangos de líneas cambiados usando CopilotChat
  local changed_ranges = M.get_changed_lines_via_copilot(file_path, opts)
  log.debug("Se encontraron " .. #changed_ranges .. " rangos de líneas modificados vía CopilotChat")

  if #changed_ranges == 0 then
    log.info("No se detectaron cambios recientes en el archivo " .. file_path)
    return {}
  end

  -- Obtener los elementos del archivo (funciones, métodos, etc.)
  local detector = require("copilotchatassist.documentation.detector")
  local elements = detector.scan_buffer(buffer)
  log.debug("Detector encontró " .. #elements .. " elementos en total")

  -- Marcar los elementos que se solapan con rangos cambiados
  local changed_elements = {}

  for _, element in ipairs(elements) do
    for _, range in ipairs(changed_ranges) do
      -- Verificar si el elemento está dentro del rango o se solapa con él
      if (element.start_line <= range.end_line and
          element.end_line >= range.start_line) then
        -- Añadir información de cambio al elemento
        element.changed = true
        element.change_type = range.type
        table.insert(changed_elements, element)
        break -- Ya encontramos un cambio para este elemento
      end
    end
  end

  log.debug("Se encontraron " .. #changed_elements .. " elementos modificados en " .. file_path)
  return changed_elements
end

-- Comando personalizado para documentar elementos modificados según CopilotChat
function M.document_modified_elements()
  local buffer = vim.api.nvim_get_current_buf()
  local doc = require("copilotchatassist.documentation")
  local git_changes = require("copilotchatassist.documentation.git_changes")

  vim.ui.select(
    {
      "Documentar elementos modificados (git local)",
      "Documentar elementos modificados (via CopilotChat - origin/main..HEAD)",
      "Documentar elementos modificados (via CopilotChat - personalizado)",
      "Cancelar"
    },
    { prompt = "¿Qué método de detección de cambios deseas usar?" },
    function(choice)
      if not choice or choice == "Cancelar" then
        return
      end

      if choice == "Documentar elementos modificados (git local)" then
        vim.ui.input({ prompt = "Número de commits a revisar (1-20): " }, function(input)
          local num_commits = tonumber(input) or 5
          num_commits = math.min(math.max(num_commits, 1), 20)

          -- Detectar cambios con git local
          local changed_elements = git_changes.detect_changed_elements(buffer, { num_commits = num_commits })
          if #changed_elements > 0 then
            doc.state.detected_items = changed_elements
            doc._show_item_selector()
          else
            vim.notify("No se detectaron cambios en los últimos " .. num_commits .. " commits", vim.log.levels.INFO)
          end
        end)
      elseif choice == "Documentar elementos modificados (via CopilotChat - origin/main..HEAD)" then
        -- Iniciar spinner de progreso
        local progress = require("copilotchatassist.utils.progress")
        local options = require("copilotchatassist.options")
        local spinner_id = "document_changes_copilot"
        progress.start_spinner(spinner_id, "Getting changes from origin/main..HEAD", {
          style = options.get().progress_indicator_style,
          position = "statusline"
        })

        -- Detectar cambios con CopilotChat usando origin/main..HEAD
        local changed_elements = M.detect_changed_elements_via_copilot(buffer, { range = "origin/main..HEAD" })
        if #changed_elements > 0 then
          -- Detener spinner con éxito
          progress.stop_spinner(spinner_id, true)

          -- Mostrar spinner de resultado
          local complete_spinner_id = "document_changes_complete"
          progress.start_spinner(complete_spinner_id, "Found " .. #changed_elements .. " changed elements", {
            style = options.get().progress_indicator_style,
            position = "statusline"
          })

          -- Detener spinner de resultado después de mostrar selector
          vim.defer_fn(function()
            progress.stop_spinner(complete_spinner_id, true)
            doc.state.detected_items = changed_elements
            doc._show_item_selector()
          end, 2000)
        else
          -- Detener spinner con estado neutro
          progress.stop_spinner(spinner_id, nil)
        end
      elseif choice == "Documentar elementos modificados (via CopilotChat - personalizado)" then
        vim.ui.input({ prompt = "Rango personalizado (ej: HEAD~3..HEAD): " }, function(range)
          if not range or range == "" then
            range = "origin/main..HEAD"
          end

          -- Iniciar spinner de progreso
          local progress = require("copilotchatassist.utils.progress")
          local options = require("copilotchatassist.options")
          local spinner_id = "document_changes_custom"
          progress.start_spinner(spinner_id, "Getting changes for " .. range, {
            style = options.get().progress_indicator_style,
            position = "statusline"
          })

          -- Detectar cambios con CopilotChat usando rango personalizado
          local changed_elements = M.detect_changed_elements_via_copilot(buffer, { range = range })
          if #changed_elements > 0 then
            -- Detener spinner con éxito
            progress.stop_spinner(spinner_id, true)

            -- Mostrar spinner de resultado
            local complete_spinner_id = "document_custom_complete"
            progress.start_spinner(complete_spinner_id, "Found " .. #changed_elements .. " changed elements in " .. range, {
              style = options.get().progress_indicator_style,
              position = "statusline"
            })

            -- Detener spinner de resultado después de mostrar selector
            vim.defer_fn(function()
              progress.stop_spinner(complete_spinner_id, true)
              doc.state.detected_items = changed_elements
              doc._show_item_selector()
            end, 2000)
          else
            -- Detener spinner con estado neutro
            progress.stop_spinner(spinner_id, nil)
            log.info("No se detectaron cambios para el rango " .. range)
          end
        end)
      end
    end
  )
end

return M