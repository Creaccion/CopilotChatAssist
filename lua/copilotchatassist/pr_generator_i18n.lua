local M = {}

local log = require("copilotchatassist.utils.log")
local file_utils = require("copilotchatassist.utils.file")
local copilot_api = require("copilotchatassist.copilotchat_api")
local i18n = require("copilotchatassist.i18n")
local notify = require("copilotchatassist.utils.notify")
local response_validator = require("copilotchatassist.utils.response_validator")

-- Función local para obtener la rama actual en lugar de usar utils
local function get_current_branch()
  local handle = io.popen("git rev-parse --abbrev-ref HEAD")
  local branch = handle:read("*a"):gsub("%s+", "")
  handle:close()
  return branch
end

-- Estado del módulo
M.state = {
  current_pr = nil,  -- Almacena información del PR actual
  pr_language = nil  -- Idioma detectado del PR
}

-- Variables adicionales para manejo de estado
M.has_template_description = false -- Indica si hay un template básico como descripción
M.pr_update_completed = false -- Indica si ya se ha completado una actualización del PR en el flujo actual

-- Función local para llamar al comando gh CLI para obtener el diff del PR actual
-- Retorna el diff o nil si no se puede obtener
function get_diff(callback)
  -- Verificar que tenemos un branch
  local branch = get_current_branch()
  if not branch or branch == "" then
    log.error("No se pudo determinar la rama actual")
    if callback then callback(nil) end
    return
  end

  -- Verificar que el callback es una función
  if type(callback) ~= "function" then
    log.error("get_diff requiere un callback válido")
    return
  end

  -- Determinar la rama base a comparar
  -- Primero intenta obtener la rama base automáticamente
  -- de la rama por defecto del repositorio, normalmente 'main'
  local base_branch

  log.debug("Obteniendo el nombre de la rama por defecto...")
  local cmd_default_branch = "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || echo origin/main"
  local handle_default = io.popen(cmd_default_branch)
  if handle_default then
    local default_branch_ref = handle_default:read("*l")
    handle_default:close()

    -- Extraer nombre de rama de la referencia (origin/main -> main)
    if default_branch_ref then
      base_branch = default_branch_ref:match("origin/([^%s]+)")
      log.debug("Rama por defecto detectada: " .. (base_branch or "desconocida"))
    end
  end

  -- Si no pudimos determinar la rama base, usar 'main' como fallback
  if not base_branch then
    base_branch = "main"
    log.debug("No se pudo determinar la rama base, usando 'main' como fallback")
  end

  -- Registrar rama base detectada para diagnóstico
  log.debug("Rama base detectada: " .. base_branch)

  -- Crear el comando diff
  local diff_command = "git diff origin/" .. base_branch .. "..." .. "HEAD"
  log.debug("Comando diff: " .. diff_command)

  log.debug("Obteniendo diff de forma asíncrona...")
  local job_id = vim.fn.jobstart(diff_command, {
    on_stdout = function(_, data, _)
      if not data or #data <= 1 then
        log.warn("No se encontraron cambios en el diff")
        callback(nil)
        return
      end

      local diff = table.concat(data, "\n")
      log.debug("Diff obtenido correctamente, longitud: " .. #diff .. " bytes")
      callback(diff)
    end,
    on_stderr = function(_, data, _)
      local error_msg = table.concat(data, "\n")
      if error_msg and error_msg ~= "" then
        log.error("Error obteniendo diff: " .. error_msg)
      end

      -- No fallar inmediatamente, verificar primero stdout
      if not data or #data == 0 then
        callback(nil)
      end
    end,
    stdout_buffered = true,
    stderr_buffered = true
  })

  if job_id <= 0 then
    log.error("Fallo al iniciar job para obtener diff")
    callback(nil)
  end
end

-- Genera un título para el PR basado en los cambios
function M.generate_pr_title(callback)
  -- Importar options aquí para asegurar que está disponible
  local options = require("copilotchatassist.options")

  -- Si callback no es una función, crear una función dummy
  if type(callback) ~= "function" then
    callback = function(_) end
  end

  get_diff(function(diff)
    if not diff or diff == "" then
      log.debug("No se encontraron cambios para generar un título")
      callback(nil)
      return
    end

    -- Siempre usar el idioma específico para PR o el configurado, sin depender de detección
    local language = options.get().pr_language or options.get().language
    log.debug("Usando idioma para PR: " .. language)
    local title_prefix = i18n.t("pr.title_prefix")

    local prompt
    if language == "spanish" then
      prompt = string.format([[
    Eres un asistente experto en crear títulos para Pull Requests.
    Genera un título conciso para un Pull Request basado en los cambios proporcionados.
    El título debe:
    - Comenzar con "%s"
    - Ser breve (menos de 70 caracteres)
    - Capturar la esencia del cambio
    - Estar escrito en español
    - No incluir número de ticket a menos que aparezca explícitamente en el diff

    Proporciona solamente el título, sin explicaciones adicionales.

    Cambios:
    %s
    ]], title_prefix, diff)
    else
      prompt = string.format([[
    You're an expert assistant in creating Pull Request titles.
    Generate a concise title for a Pull Request based on the provided changes.
    The title should:
    - Start with "%s"
    - Be brief (less than 70 characters)
    - Capture the essence of the change
    - Be written in English
    - Do not include a ticket number unless it explicitly appears in the diff

    Provide only the title, no additional explanations.

    Changes:
    %s
    ]], title_prefix, diff)
    end

    log.debug("Generating PR title with CopilotChat...")
    copilot_api.ask(prompt, {
      callback = function(response)
        local title = response or ""
        if title ~= "" then
          log.debug("PR title generated.")
          callback(title)
        else
          log.debug("Failed to generate PR title.")
          callback(nil)
        end
      end
    })
  end)
end

-- Función para extraer contenido de la respuesta (compartida)
-- Función para extraer contenido de la respuesta (ahora usa response_validator)
function M.extract_content_from_response(response)
  log.debug("Extrayendo contenido de respuesta usando validador centralizado")

  -- Si la respuesta contiene etiquetas de título, extraerlas antes de procesar
  local extracted_title = nil
  local content_without_title = response

  if type(response) == "string" then
    -- Intentar extraer el título si existe
    extracted_title = response:match("<pr_title>(.-)</pr_title>")

    -- Si se encontró un título, guardarlo para uso posterior y eliminarlo del contenido
    if extracted_title then
      log.debug("Título encontrado en extract_content_from_response: " .. extracted_title)

      -- Guardar el título para uso posterior si aún no ha sido guardado
      if not M.last_suggested_title then
        M.last_suggested_title = extracted_title
        log.info("Título extraído y guardado: '" .. extracted_title .. "'")
      end

      -- Eliminar las etiquetas de título
      content_without_title = response:gsub("<pr_title>.-</pr_title>", "")
      -- Limpiar posibles líneas vacías al inicio
      content_without_title = content_without_title:gsub("^%s*\n", "")
    end
  end

  -- Procesar la respuesta sin el título
  local processed_content = response_validator.process_response(content_without_title, 20)

  -- Verificar que no queden etiquetas de título en el contenido procesado
  if type(processed_content) == "string" then
    processed_content = processed_content:gsub("<pr_title>.-</pr_title>", "")
    -- Limpiar posibles líneas vacías al inicio que pudieran quedar
    processed_content = processed_content:gsub("^%s*\n", "")
  end

  return processed_content
end

-- Función para actualizar el PR con vista previa
function M.update_pr_with_preview(description, update_title, use_preview, callback)
  -- Registrar la operación con el gestor de estado si está disponible
  local operation = nil
  local state_manager = nil
  pcall(function()
    state_manager = require("copilotchatassist.utils.state_manager")
    operation = state_manager.start_operation("pr_preview")
  end)

  -- Validar descripción usando el validador centralizado
  if not description then
    log.error("Error crítico: description es nil en update_pr_with_preview")
    notify.error("Error: Descripción vacía, no se puede actualizar el PR")
    if callback then callback(false) end

    -- Completar la operación si está disponible el gestor de estado
    if operation then
      operation:cancel("Descripción es nil")
    end

    return false
  end

  -- Si la descripción no es un string, intentar convertirla usando el validador
  if type(description) ~= "string" then
    log.warn("Descripción no es un string, intentando convertir usando validador")
    description = response_validator.process_response(description, 20)

    if not description then
      log.error("No se pudo convertir descripción a string válido")
      notify.error("Error: Formato de descripción inválido")
      if callback then callback(false) end

      -- Completar la operación si está disponible el gestor de estado
      if operation then
        operation:cancel("Descripción no es string ni convertible")
      end

      return false
    end
  end

  -- Verificar descripción vacía o demasiado corta
  if #description < 20 then
    log.error("Descripción demasiado corta (" .. #description .. " caracteres), no se puede actualizar el PR")
    notify.error("Descripción demasiado corta, no se puede actualizar el PR")
    if callback then callback(false) end

    -- Completar la operación si está disponible el gestor de estado
    if operation then
      operation:cancel("Descripción demasiado corta")
    end

    return false
  end

  if use_preview then
    -- Determinar qué método de vista previa usar
    local options = require("copilotchatassist.options")
    local use_temp_file = options.get().pr_use_temp_file or false

    if use_temp_file then
      return M.preview_with_temp_file(description, update_title, callback)
    else
      return M.preview_with_external_editor(description, update_title, callback)
    end
  end

  -- Guardar la descripción para depuración
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")
  local debug_file = debug_dir .. "/pr_content_to_update.txt"
  local df = io.open(debug_file, "w")
  if df then
    df:write(description)
    df:close()
    log.debug("Contenido a actualizar guardado en " .. debug_file)
  end

  -- Generar título si se solicitó actualizar el título
  if update_title then
    log.debug("Preparando para actualizar título")

    -- Obtener título actual y el ticket de Jira de la rama
    local cmd_title = 'gh pr view --json title --jq .title 2>/dev/null'
    local handle_title = io.popen(cmd_title)
    local current_title = handle_title and handle_title:read("*a") or ""
    if handle_title then handle_title:close() end
    current_title = current_title:gsub("%s+$", "") -- Eliminar espacios al final

    local branch = get_current_branch()
    local ticket = branch:match("^([A-Z]+%-%d+)")

    -- Preparar el nuevo título con el formato TICKET: descripción
    local new_title = current_title
    if ticket then
      -- Verificar si ya tiene el ticket
      if not current_title:match("^" .. ticket .. "[:; ]") then
        -- Comprobar si ya tiene algún formato de ticket
        local existing_ticket = current_title:match("^([A-Z]+%-%d+)[:; ]")
        if existing_ticket then
          -- Reemplazar el ticket existente
          new_title = current_title:gsub("^" .. existing_ticket, ticket)
        else
          -- Añadir el ticket al inicio
          new_title = ticket .. ": " .. current_title
        end
      end
    end

    -- Si se solicitó vista previa
    if use_preview then
      log.debug("Intentando crear vista previa para el PR")

      -- La vista previa puede fallar en entornos remotos o sin interfaz gráfica
      local buffer_utils = require("copilotchatassist.utils.buffer")
      local success, error_msg = pcall(function()
        log.debug("Creando vista previa con título y descripción")
        log.debug("Longitud de la descripción: " .. #description .. " bytes")

        -- Para asegurar que no haya errores con la longitud del título
        if not new_title or new_title == "" then
          new_title = "Draft Title"
          log.warn("Título vacío, usando título genérico")
        end

        local preview_success, preview_result = pcall(buffer_utils.create_pr_preview, new_title, description,
        function(edited_title, edited_description)
          -- Actualizar con los valores editados
          log.debug("Actualizando PR con contenido editado por el usuario")

          -- Actualizar la descripción
          M.update_pr_content(edited_description, false)

          -- Actualizar el título si hay ticket
          if ticket and edited_title and edited_title ~= "" then
            -- Asegurar que el título tenga el formato correcto con el ticket
            if not edited_title:match("^" .. ticket .. "[:; ]") then
              local title_without_ticket = edited_title:gsub("^[A-Z]+%-%d+[:; ]%s*", "")
              edited_title = ticket .. ": " .. title_without_ticket
            end

            -- Actualizar título
            local cmd = string.format("gh pr edit --title '%s'", edited_title)
            local result = os.execute(cmd)

            if result == 0 or result == true then
              log.info("Título del PR actualizado correctamente: " .. edited_title)
            else
              log.error("Error al actualizar el título del PR")
            end
          end

          -- Llamar al callback si existe
          if callback then
            callback(true)
          end
        end,
        function()
          -- Cancelado por el usuario
          log.info("Actualización de PR cancelada por el usuario")
          notify.info("Actualización de PR cancelada")

          if callback then
            callback(false)
          end
        end
        )

        if not preview_success then
          log.error("Error al crear ventana de vista previa: " .. tostring(preview_result))
          -- Si falla la creación de la vista previa, intentar actualizar directamente
          return M.update_pr_with_preview(description, update_title, false)
        end
      end)

      if not success then
        log.error("Error al crear vista previa: " .. tostring(error_msg))
        -- Si la vista previa falla, intentar actualización directa
        return M.update_pr_with_preview(description, update_title, false)
      end

      return true
    else
      -- Actualización directa sin vista previa
      local update_success = M.update_pr_content(description, false)

      -- Si la actualización fue exitosa y se debe actualizar el título
      if update_success and update_title and ticket then
        local title_cmd = string.format("gh pr edit --title '%s'", new_title)
        local title_result = os.execute(title_cmd)

        if title_result == 0 or title_result == true then
          log.info("Título del PR actualizado correctamente: " .. new_title)
        else
          log.error("Error al actualizar el título del PR")
        end
      end

      if callback then
        callback(update_success)
      end

      return update_success
    end
  else
    -- No se requiere actualizar título
    if use_preview then
      -- Mostrar solo la descripción para edición
      local buffer_utils = require("copilotchatassist.utils.buffer")
      log.debug("Creando vista previa solo con descripción")
      log.debug("Longitud de la descripción: " .. #description .. " bytes")

      local success, result = pcall(function()
        return buffer_utils.create_preview_buffer("PR Description Preview", description,
          function(edited_content)
            -- Actualizar con el contenido editado
            local update_success = M.update_pr_content(edited_content, false)
            if callback then
              callback(update_success)
            end
          end,
          function()
            -- Cancelado por el usuario
            log.info("Actualización de PR cancelada por el usuario")
            notify.info("Actualización de PR cancelada")

            if callback then
              callback(false)
            end
          end
        )
      end)

      if not success then
        log.error("Error al crear vista previa: " .. tostring(result))
        -- Si la vista previa falla, intentar actualización directa
        return M.update_pr_with_preview(description, update_title, false)
      end

      return true
    else
      -- Actualización directa sin vista previa
      local success = M.update_pr_content(description, false)

      if callback then
        callback(success)
      end

      return success
    end
  end
end

-- Función para realizar la actualización del contenido del PR
function M.update_pr_content(content, notify_success)
  -- Valor por defecto para notify_success
  if notify_success == nil then
    notify_success = true
  end

  -- Crear un archivo temporal para la actualización
  local tmpfile = "/tmp/copilot_pr_update_" .. os.time() .. ".md"
  log.debug("Usando archivo temporal: " .. tmpfile)

  local tmp_f, tmp_err = io.open(tmpfile, "w")
  if not tmp_f then
    log.error("Error al crear archivo temporal: " .. tostring(tmp_err))
    notify.error("Error al crear archivo temporal para PR")
    return false
  end

  -- Escribir contenido al archivo temporal
  local write_ok, write_err = tmp_f:write(content)
  if not write_ok then
    log.error("Error al escribir en archivo temporal: " .. tostring(write_err))
    tmp_f:close()
    notify.error("Error al escribir descripción de PR")
    return false
  end

  tmp_f:close()
  log.debug("Archivo temporal escrito correctamente")

  -- Ejecutar gh CLI directamente de forma sincrónica
  local cmd = string.format("gh pr edit --body-file '%s'", tmpfile)
  log.debug("Ejecutando comando: " .. cmd)

  local result = os.execute(cmd)
  log.debug("Resultado de comando: " .. tostring(result))

  -- Verificar resultado
  if result == 0 or result == true then
    log.info("PR actualizado exitosamente")
    if notify_success then
      notify.success("PR description updated successfully")
    end
    return true
  else
    -- Intentar método alternativo como último recurso
    log.error("Error al actualizar PR, código " .. tostring(result))
    log.debug("Intentando método alternativo")

    -- Comando alternativo que puede ser más compatible
    local alt_cmd = string.format("cat '%s' | gh pr edit --body-file -", tmpfile)
    log.debug("Ejecutando comando alternativo: " .. alt_cmd)

    local alt_result = os.execute(alt_cmd)
    log.debug("Resultado de comando alternativo: " .. tostring(alt_result))

    if alt_result == 0 or alt_result == true then
      log.info("PR actualizado con éxito usando método alternativo")
      if notify_success then
        notify.success("PR description updated successfully")
      end
      return true
    else
      log.error("Ambos métodos de actualización fallaron. Código: " .. tostring(alt_result))
      notify.error("Error al actualizar PR description")
      return false
    end
  end
end

function M.ultra_direct_update(response, update_title, use_preview)
  log.debug("Usando enfoque ultra-directo para actualizar PR")

  -- Registrar la operación con el gestor de estado si está disponible
  local operation = nil
  local state_manager = nil
  pcall(function()
    state_manager = require("copilotchatassist.utils.state_manager")
    operation = state_manager.start_operation("pr_update")
  end)

  -- Use_preview es opcional, por defecto a true
  use_preview = use_preview ~= false

  log.debug("Usando vista previa: " .. tostring(use_preview))
  log.debug("Actualizar título: " .. tostring(update_title))

  -- Extraer título si está disponible en formato <pr_title>
  local extracted_title = nil
  if type(response) == "string" then
    extracted_title = response:match("<pr_title>(.-)</pr_title>")
    if extracted_title then
      log.debug("Título encontrado en la respuesta: " .. extracted_title)
      -- Guardar el título para uso posterior
      M.last_suggested_title = extracted_title
    end
  end

  -- Preparar descripción desde la respuesta usando el validador
  local content_to_use = M.extract_content_from_response(response)

  if not content_to_use then
    log.error("No se pudo extraer contenido válido de la respuesta")

    -- Completar la operación si está disponible el gestor de estado
    if operation then
      operation:cancel("Respuesta inválida")
    end

    return false
  end

  -- Guardar el contenido para depuración
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")
  local debug_file = debug_dir .. "/ultra_direct_content.txt"
  local df = io.open(debug_file, "w")
  if df then
    df:write(content_to_use)
    df:close()
    log.debug("Contenido extraído guardado en " .. debug_file)
  end

  -- Usar la función de actualización con vista previa
  -- Asegurarnos de que update_title se pase correctamente
  if update_title == nil then
    update_title = true  -- Por defecto, actualizar título si hay uno extraído
  end

  return M.update_pr_with_preview(content_to_use, update_title, use_preview)
end

function M.generate_pr_description(callback)
  -- Evitar generaciones múltiples concurrentes
  if M.pr_generation_in_progress or M.pr_update_in_progress then
    log.warn("Ya hay una generación o actualización de PR en curso, evitando operación duplicada")
    if callback then callback(nil) end
    return
  end

  -- Resetear variables de control
  log.debug("Iniciando nueva generación de descripción PR")

  -- Añadir información sobre template
  if M.has_template_description then
    log.info("Generando descripción a partir de un template básico detectado")
  end

  -- Limpiar cualquier notificación existente para evitar conflictos
  notify.clear()

  -- Verificar si ha pasado suficiente tiempo desde la última generación exitosa
  -- para evitar múltiples generaciones en un corto periodo
  if M.last_generation_time then
    local time_elapsed = os.difftime(os.time(), M.last_generation_time)
    if time_elapsed < 10 then  -- 10 segundos como mínimo entre operaciones
      log.warn("Demasiadas operaciones de PR en corto tiempo. Espera unos segundos.")
      if callback then callback(nil) end
      return
    end
  end

  M.pr_generation_in_progress = true

  -- Importar options aquí para asegurar que está disponible
  local options = require("copilotchatassist.options")

  -- Si callback no es una función, crear una función dummy
  if type(callback) ~= "function" then
    callback = function(_) end
  end

  -- Función wrapper para liberar el flag de generación en curso
  local wrapped_callback = function(result)
    M.pr_generation_in_progress = false
    callback(result)
  end

  log.debug("Iniciando generación de descripción del PR, llamando a get_diff")
  get_diff(function(diff)
    if not diff or diff == "" then
      log.debug("No se encontraron cambios para generar una descripción")
      wrapped_callback(nil)
      return
    end

    -- Detectar el tipo de cambios (solo para diagnóstico)
    local file_count = select(2, diff:gsub("diff --git", ""))
    log.debug("Analizando cambios en " .. file_count .. " archivos")

    -- Siempre usar el idioma específico para PR o el configurado, sin depender de detección
    local language = options.get().pr_language or options.get().language
    log.debug("Usando idioma configurado para PR: " .. language)

    -- Crear prompt basado en idioma incluyendo generación de título
    local prompt
    if language == "spanish" then
      prompt = string.format([[
      Eres un asistente experto en generar descripciones para Pull Requests.
      Genera una descripción clara y estructurada para un Pull Request basado en los cambios proporcionados.

      También proporciona un título conciso y descriptivo para el PR que capture la esencia de los cambios.

      La respuesta debe tener este formato exacto:
      <pr_title>TÍTULO CONCISO AQUÍ (menos de 70 caracteres)</pr_title>

      ## Contexto
      [Descripción detallada del propósito de este cambio y lo que hace]

      ## Pruebas
      [Descripción de cómo se probó este cambio]

      ## Feedback
      [Descripción de qué tipo de feedback necesitas de los revisores]

      El título debe:
      - Ser conciso (menos de 70 caracteres)
      - Utilizar verbos en presente (ej: "Añade", "Corrige", "Mejora")
      - Capturar la esencia del cambio
      - No incluir el número de ticket
      - Estar escrito en español

      La descripción debe:
      - Ser detallada pero concisa
      - Explicar el propósito y los efectos de los cambios
      - Estar escrita en español

      Si los cambios incluyen algún diagrama o representación visual, incluye un diagrama mermaid si es apropiado.

      Cambios:
      %s
      ]], diff)
    else
      prompt = string.format([[
      You are an expert assistant in generating Pull Request descriptions.
      Generate a clear and structured description for a Pull Request based on the provided changes.

      Also provide a concise, descriptive title for the PR that captures the essence of the changes.

      The response must follow this exact format:
      <pr_title>CONCISE TITLE HERE (less than 70 characters)</pr_title>

      ## Context
      [Detailed description of why you are making this change and what this change does]

      ## Testing
      [Description of how you tested this change]

      ## Feedback
      [Description of what feedback you would like from reviewers]

      The title should:
      - Be concise (less than 70 characters)
      - Use present tense verbs (e.g., "Add", "Fix", "Improve")
      - Capture the essence of the changes
      - Not include any ticket number
      - Be written in English

      The description should:
      - Be detailed but concise
      - Explain the purpose and effects of the changes
      - Be written in English

      If the changes include any diagram or visual representation, include a mermaid diagram if appropriate.

      Changes:
      %s
      ]], diff)
    end

    log.debug("Generando descripción del PR con CopilotChat...")
    local progress = require("copilotchatassist.utils.progress")
    progress.start_spinner("generate_pr", i18n.t("pr.generating"))

    -- Flag para rastrear si esta operación ha sido reemplazada
    local operation_id = tostring(os.time()) .. "_" .. math.random(1000, 9999)
    M.pr_operation_id = operation_id

    -- Timer de seguridad para asegurar que el spinner no quede indefinidamente
    local timeout_timer = nil
    local timeout_occurred = false
    local timeout_duration = 45000  -- 45 segundos

    timeout_timer = vim.defer_fn(function()
      -- Solo continuar si esta operación sigue siendo la actual
      if M.pr_operation_id ~= operation_id then
        log.debug("Timeout ignorado porque la operación " .. operation_id .. " ya no es la actual")
        return
      end

      log.warn("Timeout alcanzado para generación de PR, intentando método de fallback")
      timeout_occurred = true

      -- Intentar obtener descripción del PR existente como fallback
      local existing_description = get_pr_description_sync()
      if existing_description and existing_description ~= "" then
        log.debug("Usando descripción existente del PR como fallback")
        progress.stop_spinner("generate_pr")
        M.pr_generation_in_progress = false
        wrapped_callback(existing_description)
      else
        -- Si no hay descripción existente, notificar el fallo
        log.error("No se pudo generar la descripción del PR dentro del tiempo límite")
        notify.error("Timeout generando descripción del PR")
        progress.stop_spinner("generate_pr", false)
        M.pr_generation_in_progress = false
        wrapped_callback(nil)
      end
    end, timeout_duration)

    -- Generar la descripción usando CopilotChat
    copilot_api.ask(prompt, {
      callback = function(response)
        -- Si la operación es diferente a la actual, ignorar
        if M.pr_operation_id ~= operation_id then
          log.debug("Ignorando respuesta de operación " .. operation_id .. " porque ya no es la actual")
          return
        end

        -- Si ya ocurrió un timeout, ignorar esta callback
        if timeout_occurred then
          log.debug("Response received after timeout, ignoring")
          return
        end

        -- Cancelar el timer de timeout ya que llegó la respuesta
        if timeout_timer then
          timeout_timer:close()
        end

        progress.stop_spinner("generate_pr")
        log.debug("Descripción del PR generada con éxito")

        -- Extraer título generado, si existe
        local extracted_title = nil
        if type(response) == "string" then
          -- Guardar la respuesta original para diagnóstico
          local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
          vim.fn.mkdir(debug_dir, "p")
          local debug_file = debug_dir .. "/original_response.txt"
          local f = io.open(debug_file, "w")
          if f then
            f:write(response)
            f:close()
            log.debug("Respuesta original guardada en: " .. debug_file)
          end

          -- Buscar el patrón de título con varias expresiones regulares para mayor robustez
          extracted_title = response:match("<pr_title>(.-)</pr_title>")

          -- Log detallado sobre la búsqueda de título
          if extracted_title then
            log.debug("Título encontrado con patrón principal: " .. extracted_title)
          else
            log.debug("No se encontró título con patrón principal, intentando alternativas...")

            -- Intentar con un patrón más flexible
            extracted_title = response:match("[<]pr_title[>]([^<]+)[<]/pr_title[>]")
            if extracted_title then
              log.debug("Título encontrado con patrón alternativo 1: " .. extracted_title)
            else
              -- Intentar un patrón aún más flexible
              extracted_title = response:match("[Tt][ií][t][u]?[l]?[o]?:?%s*([^\n]+)")
              if extracted_title then
                log.debug("Título encontrado con patrón alternativo 2: " .. extracted_title)
              else
                log.debug("No se pudo encontrar ningún título en la respuesta")
              end
            end
          end

          if extracted_title then
            -- Limpiar título de posibles espacios o caracteres indeseados
            extracted_title = extracted_title:gsub("^%s+", ""):gsub("%s+$", "")

            -- Guardar el título para uso posterior
            M.last_suggested_title = extracted_title
            log.info("Título extraído automáticamente: '" .. extracted_title .. "'")
            notify.info("Título sugerido: " .. extracted_title)

            -- También guardarlo en un archivo específico para diagnóstico
            local title_file = debug_dir .. "/extracted_title.txt"
            local tf = io.open(title_file, "w")
            if tf then
              tf:write(extracted_title)
              tf:close()
            end

            -- NO eliminar la etiqueta de título aquí para que pueda ser procesada correctamente
            -- en las funciones de actualización y se mantenga la consistencia.
            -- Las etiquetas serán eliminadas por extract_content_from_response y process_and_update
            -- para evitar que aparezcan en el cuerpo del PR final
          else
            log.warn("No se encontró título en la descripción generada")
          end
        end

        M.pr_generation_in_progress = false
        wrapped_callback(response)
      end,
      system_prompt = "Eres un asistente especializado en generar descripciones claras y útiles para Pull Requests, adaptándote al idioma y estilo solicitados.",
      model = options.get().model,
      temperature = options.get().temperature,
      timeout = timeout_duration
    })
  end)
end

-- Obtener la descripción actual del PR
function M.get_pr_description(callback)
  -- Verificar que tenemos un callback válido
  if type(callback) ~= "function" then
    log.error("get_pr_description requiere un callback válido")
    return
  end

  log.debug("Verificando PR actual...")

  -- Ejecutar comando gh pr view de forma asíncrona
  local check_cmd = "gh pr view --json body --jq .body 2>/dev/null"
  local check_job_id = vim.fn.jobstart(check_cmd, {
    on_stdout = function(_, data, _)
      -- Si no hay datos o están vacíos
      if not data or #data <= 1 or (data[1] and data[1] == "") then
        log.debug("No se encontró PR para esta rama (stdout)")
        callback(nil)
        return
      end

      -- Unir los datos y eliminar espacios al final
      local desc = table.concat(data, "\n")
      if desc then
        -- Verificar si es un template básico (solo comentarios y títulos de sección)
        local desc_copy = desc:gsub("<!%-%-.-%-%->\\n?", "") -- Quitar comentarios HTML
        local clean_desc = desc_copy:gsub("##%s+[%w%s]+", "") -- Quitar encabezados
        clean_desc = clean_desc:gsub("[\\n\\r%s]+", "") -- Quitar espacios y saltos

        if clean_desc == "" then
          M.has_template_description = true
          log.debug("PR contiene solo un template básico")
        else
          M.has_template_description = false
          log.debug("PR contiene una descripción completa, no solo un template")
        end

        log.debug("Descripción del PR obtenida correctamente, longitud: " .. #desc .. " bytes")
        log.debug("Primeros 100 caracteres: " .. desc:sub(1, 100):gsub("\\n", "\\\\n") .. "...")
        callback(desc)
      end
    end,
    on_stderr = function(_, data, _)
      local error_msg = table.concat(data, "\n")

      -- Guardar el error para diagnóstico
      local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
      vim.fn.mkdir(debug_dir, "p")
      local debug_file = debug_dir .. "/gh_pr_error.txt"
      local f = io.open(debug_file, "w")
      if f then
        f:write(error_msg)
        f:close()
        log.debug("Error de gh pr guardado en " .. debug_file)
      end

      if error_msg and error_msg ~= "" then
        -- No siempre es un error crítico, a veces es informativo
        if error_msg:match("no pull request found") then
          log.debug("No se encontró PR para esta rama (stderr)")
        else
          log.error("Error verificando PR: " .. error_msg)
        end
      end

      -- No fallar inmediatamente, verificamos primero si hubo salida en stdout
      if not data or #data == 0 or (data[1] and data[1] == "") then
        callback(nil)
      end
    end,
    stdout_buffered = true,
    stderr_buffered = true
  })

  if check_job_id <= 0 then
    log.error("Fallo al iniciar job para verificar PR, intentando método sincrónico")

    -- Intentar método sincrónico como fallback
    local desc = get_pr_description_sync()
    callback(desc)
  end

  -- Configurar un temporizador de seguridad para evitar timeouts indefinidos
  vim.defer_fn(function()
    log.debug("Verificando si es necesario usar fallback por timeout")
    vim.fn.jobwait({check_job_id}, 0)

    -- Si el job sigue en ejecución después de 3 segundos, intentar método sincrónico
    if vim.fn.jobwait({check_job_id}, 0)[1] == -1 then
      log.debug("Intentando obtener descripción de PR de forma sincrónica (fallback)")
      local desc = get_pr_description_sync()
      if desc then
        callback(desc)
      end
    end
  end, 3000)  -- 3 segundos de timeout
end

-- Método sincrónico para obtener descripción de PR (fallback)
function get_pr_description_sync()
  local cmd = "gh pr view --json body --jq .body 2>/dev/null"
  local handle = io.popen(cmd)
  if not handle then return nil end

  local desc = handle:read("*a")
  handle:close()

  if desc and desc ~= "" then
    log.debug("Descripción obtenida con éxito mediante fallback sincrónico")

    -- Verificar si es un template básico
    local desc_copy = desc:gsub("<!%-%-.-%-%->\\n?", "") -- Quitar comentarios HTML
    local clean_desc = desc_copy:gsub("##%s+[%w%s]+", "") -- Quitar encabezados
    clean_desc = clean_desc:gsub("[\\n\\r%s]+", "") -- Quitar espacios y saltos

    if clean_desc == "" then
      M.has_template_description = true
      log.debug("PR tiene una descripción de template básica")
    else
      M.has_template_description = false
      log.debug("PR tiene una descripción completa, procediendo con enhancement normal")
    end

    return desc
  end

  return nil
end

-- Extraer datos estructurados del PR actual
function M.get_pr_data(callback)
  if type(callback) ~= "function" then
    log.error("get_pr_data requiere un callback válido")
    return
  end

  -- Ejecutar comando gh pr view para obtener datos JSON
  local cmd = "gh pr view --json number,title,body,url,state,isDraft 2>/dev/null"
  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if not data or #data <= 1 then
        log.debug("No se encontró PR para esta rama")
        callback(nil)
        return
      end

      -- Unir los datos y eliminar espacios al final
      local json_data = table.concat(data, "\n"):gsub("%s+$", "")

      -- Intentar parsear los datos JSON
      local ok, pr_data = pcall(vim.json.decode, json_data)
      if ok and pr_data then
        -- Guardar datos para diagnóstico
        local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
        vim.fn.mkdir(debug_dir, "p")
        local debug_file = debug_dir .. "/gh_pr_response.json"
        local f = io.open(debug_file, "w")
        if f then
          f:write(json_data)
          f:close()
          log.debug("Datos del PR guardados en " .. debug_file)
        end

        -- Guardar datos más simples para compatibilidad
        local simple_data = {
          number = pr_data.number,
          title = pr_data.title,
          url = pr_data.url
        }
        local debug_simple = io.open("/tmp/pr_debug.json", "w")
        if debug_simple then
          debug_simple:write(vim.json.encode(simple_data))
          debug_simple:close()
          log.debug("Datos simplificados del PR guardados en /tmp/pr_debug.json")
        end

        log.debug("Datos del PR obtenidos correctamente")
        callback(pr_data)
      else
        log.error("Error al parsear datos del PR: " .. (json_data:sub(1, 100) or ""))
        callback(nil)
      end
    end,
    on_stderr = function(_, data, _)
      local error_msg = table.concat(data, "\n")
      if error_msg and error_msg ~= "" then
        log.error("Error obteniendo datos del PR: " .. error_msg)
      end

      callback(nil)
    end,
    stdout_buffered = true,
    stderr_buffered = true
  })

  if job_id <= 0 then
    log.error("Fallo al iniciar job para obtener datos del PR")
    callback(nil)
  end
end

-- Actualizar el título del PR con el ticket de Jira de la rama
function M.update_pr_title_with_jira_ticket()
  log.info("Verificando si es necesario actualizar título del PR con ticket de Jira")

  -- Obtener el ticket de Jira de la rama actual
  local branch = get_current_branch()
  local ticket = branch:match("^([A-Z]+%-%d+)")

  if not ticket then
    log.debug("No se encontró ticket de Jira en la rama: " .. branch)
    return
  end

  log.debug("Ticket de Jira encontrado en rama: " .. ticket)

  -- Obtener el título actual del PR
  local cmd = 'gh pr view --json title --jq .title 2>/dev/null'
  local handle = io.popen(cmd)
  local current_title = handle and handle:read("*a") or ""
  if handle then handle:close() end

  if not current_title or current_title == "" then
    log.warn("No se pudo obtener el título del PR")
    return
  end

  current_title = current_title:gsub("%s+$", "") -- Eliminar espacios en blanco al final
  log.debug("Título actual del PR: '" .. current_title .. "'")

  -- Verificar si ya tiene este ticket de Jira en exactamente el mismo formato
  if current_title:match("^" .. ticket .. "[: ]") then
    log.debug("El título ya incluye el ticket de Jira en formato correcto: " .. current_title)
    return
  end

  -- Verificar si el título ya contiene algún otro formato de ticket Jira
  -- como ABC-123, XYZ-456, etc., al inicio
  if current_title:match("^[A-Z]+%-[0-9]+[: ]") then
    log.debug("El título ya tiene un formato de ticket Jira: " .. current_title)

    -- Verificar si hay coincidencia del número de ticket (aunque con diferente formato)
    local existing_ticket = current_title:match("^([A-Z]+%-[0-9]+)[: ]")
    if existing_ticket then
      log.debug("Ticket existente en título: " .. existing_ticket)

      -- Si el ticket en el título es diferente al de la rama, reemplazarlo
      if existing_ticket ~= ticket then
        log.debug("Reemplazando ticket " .. existing_ticket .. " por " .. ticket)
        current_title = current_title:gsub("^" .. existing_ticket, ticket)

        -- Actualizar el título del PR
        M.update_pr_title_async(current_title)

        notify.info("Título del PR actualizado con ticket de Jira: " .. ticket)
      else
        log.debug("No es necesario actualizar el título, ya tiene el ticket correcto")
      end
      return
    end
  end

  -- Si llegamos aquí, el título no tiene formato de ticket Jira
  -- Crear nuevo título con formato "JIRA-123: Título original"
  local new_title = ticket .. ": " .. current_title
  log.debug("Nuevo título del PR: '" .. new_title .. "'")

  -- Actualizar el título del PR usando método asíncrono más confiable
  M.update_pr_title_async(new_title)

  notify.info("Título del PR actualizado con ticket de Jira: " .. ticket)
end

-- Nueva función para actualizar el título del PR de forma asíncrona
function M.update_pr_title_async(title)
  if not title or title == "" then
    log.error("No se puede actualizar el título del PR: título vacío")
    return false
  end

  log.debug("Actualizando título del PR de forma asíncrona: '" .. tostring(title) .. "'")

  -- Escapar comillas en el título
  local escaped_title = title:gsub("'", "'\\''"):gsub('"', '\\"')

  -- Guardar título para diagnóstico
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")
  local debug_file = debug_dir .. "/pr_title_update.txt"
  local f = io.open(debug_file, "w")
  if f then
    f:write(title .. "\n")
    f:close()
  end

  -- Obtener datos completos del PR actual
  log.debug("Obteniendo datos del PR actual")
  local pr_number = nil
  local repo_url = nil

  -- Obtener información completa del PR
  local cmd_pr_info = "gh pr view --json number,headRepository,url --jq '{number: .number, repo: .headRepository.url, url: .url}' 2>/dev/null"
  local handle_pr = io.popen(cmd_pr_info)
  local pr_info_str = nil

  if handle_pr then
    pr_info_str = handle_pr:read("*a"):gsub("%s+$", "")
    handle_pr:close()

    log.debug("Información del PR obtenida: " .. pr_info_str)

    -- Intentar parsear la información como JSON
    local success, pr_info = pcall(vim.json.decode, pr_info_str)
    if success and pr_info and pr_info.number then
      pr_number = tonumber(pr_info.number)

      -- Asegurarse de que repo_url sea una cadena de texto
      if pr_info.repo ~= nil then
        if type(pr_info.repo) == "string" then
          repo_url = pr_info.repo
        else
          -- Convertir a cadena si no lo es
          repo_url = tostring(pr_info.repo)
        end
      end

      log.debug("Número de PR obtenido: " .. tostring(pr_number))
      log.debug("URL del repositorio: " .. tostring(repo_url or "desconocida"))
    end
  end

  -- Si no se pudo obtener a través de JSON, intentar obtener solo el número
  if not pr_number then
    log.debug("Intentando obtener solo el número del PR")
    local cmd_pr_number = "gh pr view --json number --jq .number 2>/dev/null"
    local handle_pr_number = io.popen(cmd_pr_number)
    if handle_pr_number then
      local pr_num_str = handle_pr_number:read("*a"):gsub("%s+$", "")
      handle_pr_number:close()

      if pr_num_str and pr_num_str ~= "" then
        pr_number = tonumber(pr_num_str)
        log.debug("Número de PR obtenido (método alternativo): " .. pr_number)
      end
    end
  end

  if not pr_number then
    log.error("No se pudo obtener el número de PR actual")

    -- Guardar respuesta de diagnóstico
    local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    local debug_file = debug_dir .. "/pr_info_error.txt"
    local f = io.open(debug_file, "w")
    if f then
      f:write("Comando: " .. tostring(cmd_pr_info) .. "\n")
      f:write("Respuesta: " .. tostring(pr_info_str or "vacía") .. "\n")
      f:close()
    end

    notify.error("No se pudo identificar el PR a actualizar")
    return false
  end

  -- Crear un archivo temporal con el título
  local tmpfile = "/tmp/pr_title_" .. os.time() .. ".txt"
  local tmp_f = io.open(tmpfile, "w")
  if tmp_f then
    tmp_f:write(title)
    tmp_f:close()
    log.debug("Título guardado en archivo temporal: " .. tmpfile)
  else
    log.error("No se pudo crear archivo temporal para título")
    return false
  end

  -- Intentar distintos métodos para actualizar el PR

  -- Método 1: Usando gh con el archivo temporal
  local gh_cmd = "gh pr edit " .. pr_number .. " --title \"$(cat '" .. tmpfile .. "')\""
  log.debug("Método 1: Ejecutando comando: " .. gh_cmd)
  local direct_result = os.execute(gh_cmd)

  if direct_result == 0 or direct_result == true then
    log.info("Título actualizado correctamente con método 1")
    notify.success("Título del PR actualizado correctamente")
    os.remove(tmpfile)
    return true
  end

  -- Método 2: Usando gh con el título escapado
  log.warn("Método 1 falló, intentando método 2")
  local alt_cmd = string.format("gh pr edit %d --title '%s'", pr_number, escaped_title)
  log.debug("Método 2: Ejecutando comando: " .. alt_cmd)
  local alt_result = os.execute(alt_cmd)

  if alt_result == 0 or alt_result == true then
    log.info("Título actualizado con método 2")
    notify.success("Título del PR actualizado correctamente")
    os.remove(tmpfile)
    return true
  end

  -- Método 3: Usando el flag --title-file
  log.warn("Método 2 falló, intentando método 3")
  local alt_cmd3 = string.format("gh pr edit %d --title-file '%s'", pr_number, tmpfile)
  log.debug("Método 3: Ejecutando comando: " .. alt_cmd3)
  local alt_result3 = os.execute(alt_cmd3)

  if alt_result3 == 0 or alt_result3 == true then
    log.info("Título actualizado con método 3")
    notify.success("Título del PR actualizado correctamente")
    os.remove(tmpfile)
    return true
  end

  -- Método 4: Usando una redirección de echo a --title-file -
  log.warn("Método 3 falló, intentando método 4")
  local alt_cmd4 = string.format("echo '%s' | gh pr edit %d --title-file -", escaped_title, pr_number)
  log.debug("Método 4: Ejecutando comando: " .. alt_cmd4)
  local alt_result4 = os.execute(alt_cmd4)

  if alt_result4 == 0 or alt_result4 == true then
    log.info("Título actualizado con método 4")
    notify.success("Título del PR actualizado correctamente")
    os.remove(tmpfile)
    return true
  end

  -- Método 5: Último recurso - usando la API directamente con un token de GitHub
  log.warn("Todos los métodos anteriores fallaron, intentando obtener token para método directo")

  -- Intentar obtener el token de GitHub
  local token_cmd = "gh auth token"
  local handle_token = io.popen(token_cmd)
  local github_token = nil
  if handle_token then
    github_token = handle_token:read("*a"):gsub("%s+$", "")
    handle_token:close()
  end

  if github_token and github_token ~= "" and pr_number and repo_url then
    log.debug("Intentando actualización directa con API de GitHub")

    -- Extraer owner y repo de la URL
    local owner, repo = nil, nil
    if repo_url and type(repo_url) == "string" then
      owner, repo = repo_url:match("github.com[/:]+([^/]+)/([^/%.]+)")

      -- Si no se pudo extraer, intentar con formato alternativo
      if not (owner and repo) and repo_url:match("github.com") then
        -- Intentar otras formas de extraer
        owner = repo_url:match("github.com/([^/]+)")
        if owner then
          repo = repo_url:match("github.com/" .. owner .. "/([^/%.]+)")
        end
      end

      log.debug("Información extraída del repo - Owner: " .. tostring(owner) .. ", Repo: " .. tostring(repo))
    else
      log.error("URL del repositorio no disponible o no es una cadena: " .. tostring(repo_url))
    end

    if owner and repo then
      -- Crear archivo JSON temporal para la petición
      local json_tmpfile = "/tmp/pr_title_json_" .. os.time() .. ".json"
      local json_f = io.open(json_tmpfile, "w")
      if json_f then
        json_f:write('{"title":"' .. title:gsub('"', '\\"') .. '"}')
        json_f:close()

        -- Construir comando curl
        local curl_cmd = string.format(
          'curl -s -X PATCH -H "Accept: application/vnd.github+json" -H "Authorization: token %s" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/%s/%s/pulls/%d -d @%s',
          github_token, owner, repo, pr_number, json_tmpfile
        )

        log.debug("Ejecutando comando curl (token ocultado)")
        local curl_result = os.execute(curl_cmd)
        os.remove(json_tmpfile)

        if curl_result == 0 or curl_result == true then
          log.info("Título actualizado exitosamente con API directa")
          notify.success("Título del PR actualizado correctamente")
          os.remove(tmpfile)
          return true
        end
      end
    end
  end

  -- Si llegamos aquí, todos los métodos fallaron
  log.error("Todos los métodos de actualización fallaron")
  notify.error("No se pudo actualizar el título del PR")
  os.remove(tmpfile)
  return false
end

-- Registrar comando adicional para la versión simplificada
function M.register_simple_command()
  local options = require("copilotchatassist.options")

  -- Comando para cambiar idioma
  vim.api.nvim_create_user_command("CopilotSimpleChangePRLanguage", function(opts)
    local target_language = opts.args
    if target_language == "" then
      -- Always use configured language
      target_language = options.get().language
      log.debug("Usando idioma configurado: " .. target_language)
    end
    M.simple_change_pr_language(target_language)
  end, {
    desc = "Cambiar el idioma de la descripción del PR usando método simplificado (english, spanish)",
    nargs = "?",
    complete = function()
      return {"english", "spanish"}
    end
  })

  -- Comando para corregir diagramas
  vim.api.nvim_create_user_command("CopilotFixPRDiagrams", function()
    M.fix_mermaid_diagrams()
  end, {
    desc = "Corregir diagramas Mermaid en la descripción de PR"
  })
end

-- Método simplificado para cambiar idioma que evita algunos problemas de asincronía
function M.simple_change_pr_language(target_language)
  -- Verificar y limpiar estado
  M.pr_generation_in_progress = false
  M.pr_update_in_progress = false

  -- Verificar idioma objetivo
  if not target_language or (target_language ~= "english" and target_language ~= "spanish") then
    notify.error("Idioma no soportado: " .. tostring(target_language))
    return
  end

  log.info("Cambiando idioma de PR a: " .. target_language)

  -- Obtener descripción actual del PR de forma sincrónica
  local cmd = "gh pr view --json body --jq .body"
  local handle = io.popen(cmd)
  if not handle then
    notify.error("No se pudo acceder al PR actual")
    return
  end

  local description = handle:read("*a")
  handle:close()

  if not description or description == "" then
    notify.error("No se encontró PR o está vacío")
    return
  end

  log.debug("Descripción actual del PR obtenida, longitud: " .. #description)

  -- Determinar el idioma actual
  local detected_language = nil
  local first_1000_chars = description:sub(1, 1000)
  local spanish_count = select(2, first_1000_chars:gsub("[áéíóúñÁÉÍÓÚÑ]", "")) + select(2, first_1000_chars:gsub("\\n## [^\\n]*\\n", "")) * 0.1
  local english_count = select(2, first_1000_chars:gsub("[a-zA-Z]", "")) * 0.01 + select(2, first_1000_chars:gsub("\\n## [^\\n]*\\n", "")) * 0.1

  if spanish_count > english_count then
    detected_language = "spanish"
  else
    detected_language = "english"
  end

  log.info("Idioma detectado en descripción actual: " .. detected_language)

  -- Si el idioma ya es el deseado, notificar y salir
  if detected_language == target_language then
    notify.info("La descripción del PR ya está en " .. target_language)
    return
  end

  -- Iniciar indicador de progreso
  local progress = require("copilotchatassist.utils.progress")
  progress.start_spinner("translate_pr", "Traduciendo descripción del PR a " .. target_language)

  -- Crear prompt para traducir la descripción
  local prompt
  if target_language == "spanish" then
    prompt = string.format([[
    Traduce la siguiente descripción de un Pull Request al español.
    Mantén el formato, incluyendo los encabezados y las secciones.
    Si hay bloques de código o diagramas mermaid, no los traduzcas.
    Asegúrate de traducir todo el contenido informativo pero mantén los nombres técnicos originales.

    %s
    ]], description)
  else
    prompt = string.format([[
    Translate the following Pull Request description to English.
    Keep the format, including headers and sections.
    Do not translate code blocks or mermaid diagrams.
    Make sure to translate all informative content but keep original technical names.

    %s
    ]], description)
  end

  -- Enviar solicitud a Copilot para traducir
  local options = require("copilotchatassist.options")
  copilot_api.ask(prompt, {
    callback = function(response)
      -- Completar spinner
      progress.stop_spinner("translate_pr")

      -- Verificar respuesta
      if not response or response == "" then
        log.error("Error al traducir la descripción del PR")
        notify.error("Error al traducir la descripción del PR")
        return
      end

      log.debug("Descripción traducida recibida, longitud: " .. #response)

      -- Actualizar PR con la descripción traducida
      local success = M.update_pr_content(response)
      if success then
        M.state.pr_language = target_language
        notify.success("Descripción del PR traducida a " .. target_language)
      else
        notify.error("Error al actualizar la descripción del PR traducida")
      end
    end,
    system_prompt = "Eres un asistente especializado en traducir descripciones técnicas de Pull Requests, manteniendo el formato y la precisión técnica.",
    model = options.get().model,
    temperature = 0.2,  -- Temperatura baja para traducción más precisa
    timeout = 30000     -- 30 segundos máximo
  })
end

-- Reparar diagrams mermaid en la descripción del PR
function M.fix_mermaid_diagrams()
  -- Obtener descripción actual del PR de forma sincrónica
  local cmd = "gh pr view --json body --jq .body"
  local handle = io.popen(cmd)
  if not handle then
    notify.error("No se pudo acceder al PR actual")
    return
  end

  local description = handle:read("*a")
  handle:close()

  if not description or description == "" then
    notify.error("No se encontró PR o está vacío")
    return
  end

  log.debug("Descripción actual del PR obtenida, longitud: " .. #description)

  -- Verificar si hay diagramas mermaid
  local has_mermaid = description:match("```mermaid")
  if not has_mermaid then
    notify.info("No se encontraron diagramas mermaid para corregir")
    return
  end

  -- Crear prompt para corregir diagramas
  local prompt = string.format([[
  Corrige la sintaxis de los diagramas mermaid en esta descripción de Pull Request.
  Sólo modifica los bloques de código mermaid, dejando el resto del texto exactamente igual.
  No cambies el formato, los encabezados, ni añadas o quites contenido fuera de los diagramas.

  Asegúrate de que todos los diagramas:
  - Tengan la sintaxis correcta para mermaid
  - Usen las notaciones correctas para el tipo de diagrama (flowchart, sequence, etc.)
  - Tengan todas las conexiones correctamente definidas

  Descripción original con diagramas para corregir:
  %s
  ]], description)

  -- Mostrar indicador de progreso
  local progress = require("copilotchatassist.utils.progress")
  progress.start_spinner("fix_diagrams", "Corrigiendo diagramas mermaid")

  -- Enviar solicitud a Copilot para corregir
  copilot_api.ask(prompt, {
    callback = function(response)
      -- Completar spinner
      progress.stop_spinner("fix_diagrams")

      -- Verificar respuesta
      if not response or response == "" then
        log.error("Error al corregir diagramas mermaid")
        notify.error("Error al corregir diagramas mermaid")
        return
      end

      log.debug("Descripción con diagramas corregidos recibida, longitud: " .. #response)

      -- Actualizar PR con la descripción corregida
      local success = M.update_pr_content(response)
      if success then
        notify.success("Diagramas mermaid corregidos exitosamente")
      else
        notify.error("Error al actualizar la descripción con diagramas corregidos")
      end
    end,
    system_prompt = "Eres un asistente especializado en corregir diagramas mermaid en descripciones de Pull Request.",
    temperature = 0.1,  -- Temperatura muy baja para correcciones precisas
    timeout = 20000     -- 20 segundos máximo
  })
end

-- Cambiar el idioma de la descripción del PR
function M.change_pr_language(target_language)
  -- Verificar idioma objetivo
  if not target_language or (target_language ~= "english" and target_language ~= "spanish") then
    notify.error("Idioma no soportado: " .. tostring(target_language))
    return
  end

  log.info("Cambiando idioma de PR a: " .. target_language)

  M.get_pr_description(function(description)
    if not description or description == "" then
      notify.error("No se encontró descripción de PR para traducir")
      return
    end

    log.debug("Descripción actual del PR obtenida, longitud: " .. #description)

    -- Detectar el idioma actual usando un texto de muestra
    local detected_language = "unknown"

    -- Texto de muestra para detección de idioma (primeros 1000 caracteres)
    local sample_text = description:sub(1, 1000)
    log.debug("Texto demasiado largo, analizando una muestra de 1000 caracteres")

    -- Contar caracteres específicos de español vs inglés
    local spanish_count = select(2, sample_text:gsub("[áéíóúñÁÉÍÓÚÑ]", ""))
    local english_count = select(2, sample_text:gsub("\\bthe\\b|\\band\\b|\\bwith\\b|\\bfor\\b", ""))

    log.debug("Detección de idioma - Español: " .. spanish_count .. ", Inglés: " .. english_count)

    if spanish_count > english_count then
      detected_language = "spanish"
    else
      detected_language = "english"
    end

    log.info("Idioma detectado en la descripción del PR: " .. detected_language)

    -- Si el idioma ya es el deseado, notificar y salir
    if detected_language == target_language then
      M.state.pr_language = target_language
      notify.info("La descripción del PR ya está en " .. target_language)
      return
    end

    -- Traducir la descripción
    log.info("Idioma configurado para usar: " .. target_language)

    -- Iniciar indicador de progreso
    local progress = require("copilotchatassist.utils.progress")
    progress.start_spinner("translate_pr", "Traduciendo descripción del PR a " .. target_language)

    -- Crear prompt para traducir la descripción
    local prompt
    if target_language == "spanish" then
      prompt = string.format([[
      Traduce la siguiente descripción de un Pull Request del inglés al español.
      Mantén el formato, incluyendo los encabezados y las secciones.
      Si hay bloques de código o diagramas mermaid, no los traduzcas.
      Asegúrate de traducir todo el contenido informativo pero mantén los nombres técnicos originales.

      %s
      ]], description)
    else
      prompt = string.format([[
      Translate the following Pull Request description from Spanish to English.
      Keep the format, including headers and sections.
      Do not translate code blocks or mermaid diagrams.
      Make sure to translate all informative content but keep original technical names.

      %s
      ]], description)
    end

    -- Enviar solicitud a Copilot para traducir
    local options = require("copilotchatassist.options")
    copilot_api.ask(prompt, {
      callback = function(response)
        -- Completar spinner
        progress.stop_spinner("translate_pr")

        -- Verificar respuesta
        if not response or response == "" then
          log.error("Error al traducir la descripción del PR")
          notify.error("Error al traducir la descripción del PR")
          return
        end

        log.debug("Descripción traducida recibida, longitud: " .. #response)

        -- Si es una respuesta en formato de tabla, extraer el contenido
        if type(response) == "table" then
          log.debug("La respuesta es una tabla, intentando extraer el contenido")

          -- Guardar la tabla para diagnóstico
          local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
          vim.fn.mkdir(debug_dir, "p")
          local debug_file = debug_dir .. "/pr_translation_table.txt"
          local df = io.open(debug_file, "w")
          if df then
            df:write(vim.inspect(response))
            df:close()
          end

          if response.content then
            response = response.content
          elseif response[1] and type(response[1]) == "string" then
            response = response[1]
          end
        end

        -- Actualizar PR con la descripción traducida
        local success = M.update_pr_content(response)
        if success then
          M.state.pr_language = target_language
          notify.success("Descripción del PR traducida a " .. target_language)
        else
          notify.error("Error al actualizar la descripción del PR traducida")
        end
      end,
      system_prompt = "Eres un asistente especializado en traducir descripciones técnicas de Pull Requests, manteniendo el formato y la precisión técnica.",
      model = options.get().model,
      temperature = 0.1,  -- Temperatura baja para traducción más precisa
    })
  end)
end

-- Función para vista previa usando editor externo
-- Función para vista previa usando archivo temporal con actualización al guardar
function M.preview_with_temp_file(description, update_title, callback)
  log.debug("Iniciando vista previa con archivo temporal (actualización al guardar)")
  log.debug("Parámetros: update_title=" .. tostring(update_title) .. ", descripción longitud=" .. #description)

  -- Verificar que description es válida
  if not description then
    log.error("Error: description es nil en preview_with_temp_file")
    notify.error("Error: Descripción vacía para la vista previa")
    if callback then callback(false) end
    return false
  end

  if type(description) ~= "string" then
    log.error("Error: description no es un string en preview_with_temp_file, es un " .. type(description))
    notify.error("Error: Formato de descripción inválido")
    if callback then callback(false) end
    return false
  end

  -- Obtener título actual del PR
  local current_title = ""
  local cmd_success, cmd_err = pcall(function()
    local handle = io.popen('gh pr view --json title --jq .title 2>/dev/null')
    current_title = handle and handle:read("*a") or ""
    if handle then handle:close() end
    current_title = current_title:gsub("%s+$", "")
  end)

  if not cmd_success then
    log.error("Error al obtener título del PR: " .. tostring(cmd_err))
    current_title = "PR Preview"
  end

  -- Crear contenido con instrucciones
  local content_with_instructions = [[# INSTRUCCIONES PARA EDITAR LA DESCRIPCIÓN DEL PR
#
# 1. Edite la descripción del PR a continuación
# 2. Guarde el archivo (Ctrl+S o :w) para publicar los cambios INMEDIATAMENTE
# 3. El PR se actualizará automáticamente cada vez que guarde
# 4. Las líneas que comienzan con # serán ignoradas en el resultado final
# 5. Verá una notificación cuando el PR se haya actualizado correctamente
#
# NOTA IMPORTANTE:
# - La actualización ocurre AUTOMÁTICAMENTE al guardar.
# - No es necesario cerrar este archivo.
# - PUEDE EDITAR el texto entre <pr_title> y </pr_title> para cambiar el título del PR
# - Las etiquetas <pr_title> y marcadores relacionados son necesarios y no deben eliminarse
#

]]

  -- Preparar un título limpio (sin ticket duplicado) para mostrar en el editor
  local clean_title = current_title
  local branch = get_current_branch()
  local ticket = branch:match("^([A-Z]+%-%d+)")

  -- Si hay un título sugerido automáticamente, usarlo si está disponible
  if M.last_suggested_title and M.last_suggested_title ~= "" then
    log.info("Usando título sugerido automáticamente para el preview: '" .. M.last_suggested_title .. "'")
    clean_title = M.last_suggested_title

    -- Añadir a la tabla de títulos alternativos para mantener historial
    if not vim.tbl_contains(M.alternative_titles or {}, M.last_suggested_title) then
      if not M.alternative_titles then M.alternative_titles = {} end
      table.insert(M.alternative_titles, M.last_suggested_title)
    end

    -- Notificar al usuario sobre el título generado
    local notify = require("copilotchatassist.utils.notify")
    notify.info("Título sugerido automáticamente: " .. M.last_suggested_title)

    -- Conservar el título en una variable permanente para posible referencia
    M.auto_suggested_title = M.last_suggested_title
    -- Limpiar la variable temporal
    M.last_suggested_title = nil
  elseif ticket and current_title:match("^" .. ticket) then
    -- Si el título ya tiene el ticket como prefijo, quitar el prefijo para evitar duplicación
    clean_title = current_title:gsub("^" .. ticket .. ":%s*", "")
  end

  -- Generar instrucciones para títulos alternativos
  local suggest_title_button = "# [Sugerir título alternativo con AI] Ejecute: :lua require('copilotchatassist.pr_generator_i18n').suggest_alternative_title()"
  local help_text = "# Para usar un título alternativo, edítelo entre las etiquetas <pr_title></pr_title> y elimine las otras opciones"

  -- Agregar título con formato especial usando etiquetas y botón para sugerir alternativa
  content_with_instructions = content_with_instructions .. "# <pr_title_marker>\n" ..
                             "# ==== TÍTULO ACTUAL ====\n" ..
                             "# <pr_title>" .. clean_title .. "</pr_title>\n" ..
                             "# ==== TÍTULOS ALTERNATIVOS ====\n" ..
                             "# " .. suggest_title_button .. "\n" ..
                             "# " .. help_text .. "\n" ..
                             "# </pr_title_marker>\n\n"

  -- Agregar la descripción a editar
  content_with_instructions = content_with_instructions .. description

  -- Crear archivo temporal con un nombre reconocible
  local branch = get_current_branch() or "branch"
  local ticket_id = branch:match("^([A-Z]+%-%d+)") or "PR"
  local timestamp = os.time()
  local tmpfile = "/tmp/copilot_pr_" .. ticket_id .. "_" .. timestamp .. ".md"

  -- Escribir contenido al archivo temporal
  log.debug("Creando archivo temporal: " .. tmpfile)
  local file = io.open(tmpfile, "w")
  if not file then
    log.error("Error al crear archivo temporal: " .. tmpfile)
    notify.error("Error al crear archivo para la vista previa")
    if callback then callback(false) end
    return false
  end

  file:write(content_with_instructions)
  file:close()

  -- Variable para rastrear cuándo fue la última actualización
  local last_update_time = 0
  local update_in_progress = false

  -- Registrar un grupo para los autocomandos
  local group_id = vim.api.nvim_create_augroup("CopilotPRPreview", { clear = true })

  -- Función para procesar el archivo y actualizar el PR
  local function process_and_update()
    -- Evitar actualizaciones simultáneas
    if update_in_progress then
      log.debug("Ya hay una actualización en progreso, ignorando")
      return
    end

    -- Mostrar spinner de progreso
    local progress = require("copilotchatassist.utils.progress")
    progress.start_spinner("update_pr", "Actualizando PR...")

    update_in_progress = true

    -- Leer el contenido del archivo temporal
    local edited_file = io.open(tmpfile, "r")
    if not edited_file then
      log.error("Error al leer archivo temporal")
      notify.error("Error al leer archivo temporal")
      update_in_progress = false
      progress.stop_spinner("update_pr", false)
      return
    end

    -- Leer el contenido editado
    local content = edited_file:read("*a")
    edited_file:close()

    -- Procesar contenido para eliminar líneas de comentario
    local lines = vim.split(content, "\n")
    local clean_content = {}
    local in_content = false
    local extracted_title = nil
    local in_title_section = false

    for _, line in ipairs(lines) do
      -- Detectar comienzo de sección de título
      if line:match("^# <pr_title_marker>") then
        in_title_section = true
        -- No incluir esta línea ni las siguientes hasta el cierre
        log.debug("Inicio de sección de título detectada")
        -- Continue para saltar esta línea
        goto continue
      end

      -- Detectar fin de sección de título
      if line:match("^# </pr_title_marker>") then
        in_title_section = false
        log.debug("Fin de sección de título detectada")
        -- Continue para saltar esta línea
        goto continue
      end

      -- Si estamos dentro de la sección de título, buscar el título principal
      if in_title_section and line:match("<pr_title>.*</pr_title>") then
        -- Extraer título para posible uso posterior
        extracted_title = line:match("<pr_title>(.*)</pr_title>")
        -- Guardar el título extraído en un archivo para diagnóstico
        local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
        vim.fn.mkdir(debug_dir, "p")
        local title_file = debug_dir .. "/extracted_title.txt"
        local tf = io.open(title_file, "w")
        if tf then
          tf:write(extracted_title or "NO TITLE FOUND")
          tf:close()
        end

        log.debug("Título extraído de etiquetas: '" .. (extracted_title or "no title found") .. "'")
        -- No incluir esta línea en el contenido final
        goto continue
      end

      -- Si estamos dentro de la sección de título, también buscar títulos alternativos
      if in_title_section and line:match("<pr_alt_title>.*</pr_alt_title>") then
        -- Extraer título alternativo para log
        local alt_title = line:match("<pr_alt_title>(.*)</pr_alt_title>")
        log.debug("Título alternativo encontrado: '" .. (alt_title or "") .. "'")
        goto continue
      end

      -- Si estamos dentro de la sección de título, ignorar todas las líneas
      if in_title_section then
        goto continue
      end

      -- Eliminar cualquier etiqueta de título que esté fuera de la sección de título
      -- Esto evita que las etiquetas <pr_title> aparezcan en el cuerpo del PR
      if line:match("<pr_title>.*</pr_title>") then
        -- Extraer solo el contenido dentro de las etiquetas
        local title_content = line:match("<pr_title>(.*)</pr_title>")

        -- Importante: Si encontramos un título fuera de la sección, también lo capturamos como título principal
        -- Esta es una modificación clave para permitir que el título aparezca en cualquier parte del documento
        if title_content and title_content ~= "" then
          extracted_title = title_content
          log.debug("⚠️ TÍTULO FUERA DE SECCIÓN ENCONTRADO: '" .. title_content .. "'")
          vim.api.nvim_echo({{"⚠️ TÍTULO FUERA DE SECCIÓN DETECTADO: " .. title_content, "WarningMsg"}}, true, {})

          -- Guardar el título extraído en un archivo para diagnóstico
          local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
          vim.fn.mkdir(debug_dir, "p")
          local title_file = debug_dir .. "/extracted_title.txt"
          local tf = io.open(title_file, "w")
          if tf then
            tf:write(extracted_title)
            tf:close()
          end
        end

        -- Si solo hay etiquetas de título en la línea, omitirla completamente
        if #line == #("<pr_title>" .. title_content .. "</pr_title>") then
          log.debug("Omitiendo línea con etiqueta de título fuera de sección")
          goto continue
        else
          -- Si hay más contenido además de las etiquetas, reemplazar solo las etiquetas
          line = line:gsub("<pr_title>.*</pr_title>", "")
        end
      end

      -- Para el resto del contenido, aplicar las reglas normales
      if not line:match("^#") then
        table.insert(clean_content, line)
        in_content = true
      elseif in_content then
        -- Si ya habíamos empezado a recopilar contenido y volvemos a encontrar un comentario,
        -- lo tratamos como parte del contenido (podría ser un comentario markdown)
        table.insert(clean_content, line)
      end

      ::continue::
    end

    -- Reconstruir contenido sin líneas de instrucción
    local final_content = table.concat(clean_content, "\n")

    -- Eliminar cualquier etiqueta de título que pudiera quedar en el texto completo
    final_content = final_content:gsub("<pr_title>.-</pr_title>", "")

    -- Eliminar líneas vacías al inicio del contenido
    final_content = final_content:gsub("^%s*\n", "")

    -- Guardar contenido procesado para diagnóstico
    local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    vim.fn.mkdir(debug_dir, "p")
    local debug_file = debug_dir .. "/pr_processed_content.txt"
    local f = io.open(debug_file, "w")
    if f then
      f:write(final_content)
      f:close()
      log.debug("Contenido procesado guardado en " .. debug_file)
    end

    -- Actualizar el PR con el contenido editado
    log.debug("Actualizando PR con contenido editado, longitud: " .. #final_content)

    -- Actualizar PR - pasar el valor original de update_title para que se actualice el título si fue solicitado
    local update_success = M.update_pr_content(final_content, update_title)

    -- Detener spinner
    progress.stop_spinner("update_pr", update_success)

    -- Notificar resultado
    if update_success then
      notify.success("PR actualizado exitosamente. Puedes seguir editando o cerrar este archivo.")

      -- Si se extrajo un título de las etiquetas y es diferente al actual, actualizarlo
      -- para actualizar el título del PR directamente
      if extracted_title and extracted_title ~= "" then
        log.info("⚠️ TÍTULO EXTRAÍDO PARA ACTUALIZAR: '" .. extracted_title .. "'")
        log.info("Título actual: '" .. (current_title or "") .. "'")

        -- Guardar el título a actualizar para diagnóstico
        local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
        vim.fn.mkdir(debug_dir, "p")
        local title_file = debug_dir .. "/pr_title_update.txt"
        local tf = io.open(title_file, "w")
        if tf then
          tf:write(extracted_title)
          tf:close()
        end

        -- Siempre actualizar el título con el valor extraído de las etiquetas
        local branch = get_current_branch()
        local ticket = branch:match("^([A-Z]+%-%d+)")

        -- Limpiar el título de posibles tickets duplicados
        if ticket then
          -- Eliminar cualquier prefijo de ticket (mismo u otro) que ya exista
          local cleaned_title = extracted_title:gsub("^[A-Z]+%-%d+:%s*", "")

          -- Ahora añadir el ticket correcto como prefijo
          extracted_title = ticket .. ": " .. cleaned_title
          log.debug("Título normalizado para evitar duplicación: " .. extracted_title)

          -- Guardar el título final con ticket en archivo para diagnóstico
          local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
          vim.fn.mkdir(debug_dir, "p")
          local backup_file = debug_dir .. "/backup_title_for_update.txt"
          local bf = io.open(backup_file, "w")
          if bf then
            bf:write(extracted_title)
            bf:close()
          end
        end

        -- Usar primero la función directa y simplificada para actualizar el título
        log.info("⚠️ INICIANDO ACTUALIZACION DE TÍTULO EXTRAÍDO: '" .. extracted_title .. "'")
        vim.api.nvim_echo({{"⚠️ INICIANDO ACTUALIZACIÓN DE TÍTULO EXTRAÍDO", "WarningMsg"}}, true, {})
        local title_update_success = M.direct_update_pr_title(extracted_title)

        if title_update_success then
          -- Marcar que ya se actualizó el título para evitar actualizaciones duplicadas
          update_title = false
          notify.success("Título del PR actualizado correctamente")
        else
          -- Intentar con el método anterior si el directo falla
          log.warn("Método directo falló, intentando método asíncrono...")
          local title_update_async_success = M.update_pr_title_async(extracted_title)

          if title_update_async_success then
            update_title = false
            notify.success("Título del PR actualizado con método alternativo")
          else
            log.error("Todos los métodos para actualizar el título fallaron")
            notify.error("No se pudo actualizar el título del PR")
          end
        end
      end

      -- Actualizar título si se solicitó pero NO se extrajo un título de las etiquetas
      -- Solo ejecutamos esta parte si no hubo un título extraído de etiquetas y update_title es true
      if update_title and not (extracted_title and extracted_title ~= "") then
        log.debug("No se extrajo título de etiquetas, usando update_title normal")

        local branch = get_current_branch()
        local ticket = branch:match("^([A-Z]+%-%d+)")

        if ticket then
          local cmd_title = 'gh pr view --json title --jq .title 2>/dev/null'
          local handle_title = io.popen(cmd_title)
          local current_title = handle_title and handle_title:read("*a") or ""
          if handle_title then handle_title:close() end
          current_title = current_title:gsub("%s+$", "")

          -- Verificar si ya tiene este ticket de Jira
          if not current_title:match("^" .. ticket .. "[: ]") then
            local new_title = ticket .. ": " .. current_title:gsub("^[A-Z]+%-%d+[:; ]%s*", "")

            -- Usar la nueva función asíncrona mejorada para actualizar el título
            log.debug("Usando función actualizada para actualizar título del PR con ticket")
            local title_update_success = M.update_pr_title_async(new_title)

            if title_update_success then
              log.info("Título del PR actualizado correctamente con ticket: " .. ticket)
              notify.success("Título del PR actualizado con ticket: " .. ticket)
            else
              log.error("Error al actualizar el título del PR con ticket")
              notify.error("Error al actualizar el título del PR con ticket")
            end
          end
        end
      end
    else
      notify.error("Error al actualizar PR. Intenta guardar de nuevo.")
    end

    -- Actualizar la hora de la última actualización
    last_update_time = os.time()
    update_in_progress = false

    -- Llamar al callback con el resultado
    if callback then
      callback(update_success)
    end
  end

  -- Crear autocmd para detectar cuando se guarda el archivo
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group_id,
    pattern = tmpfile,
    callback = function()
      log.debug("Archivo temporal guardado: " .. tmpfile)

      -- Verificar si pasaron al menos 2 segundos desde la última actualización
      -- Esto evita actualizaciones demasiado frecuentes si el usuario guarda varias veces rápidamente
      if os.time() - last_update_time < 2 then
        notify.info("Esperando antes de actualizar PR (2s entre actualizaciones)")
        log.debug("Actualización ignorada: demasiado pronto desde la última actualización")
        return
      end

      -- Esperar un momento para asegurar que el sistema de archivos esté actualizado
      log.debug("⚠️ GUARDADO DETECTADO: Iniciando procesamiento y actualización del PR...")
      vim.api.nvim_echo({{"⚠️ GUARDADO DETECTADO: Actualizando PR...", "WarningMsg"}}, true, {})
      vim.defer_fn(function()
        log.debug("⚠️ EJECUTANDO process_and_update() AHORA")
        process_and_update()
      end, 100)
    end
  })

  -- Configurar autocmd para abrir el archivo y mostrar un mensaje de ayuda
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group_id,
    pattern = tmpfile,
    callback = function()
      -- Mostrar mensaje de ayuda
      vim.defer_fn(function()
        notify.info("Edite la descripción del PR y guarde (:w) para actualizar inmediatamente.")
        -- Mostrar mensaje en pantalla con mayor visibilidad
        vim.api.nvim_echo({{"⚠️ EDITE DESCRIPCIÓN PR Y GUARDE PARA ACTUALIZAR", "WarningMsg"}}, true, {})

        -- Esperar un poco y mostrar mensaje adicional
        vim.defer_fn(function()
          notify.info("El PR se actualizará automáticamente cada vez que guarde el archivo.")
          vim.api.nvim_echo({{"⚠️ GUARDE (:w) PARA ACTUALIZAR TÍTULO Y DESCRIPCIÓN", "WarningMsg"}}, true, {})
          -- Log para debug
          log.debug("IMPORTANTE: Los mensajes de actualización de PR han sido mostrados al usuario")
        end, 2000)
      end, 200)
    end,
    once = true -- Solo ejecutar una vez
  })

  -- Configurar autocmd para limpiar cuando se cierre el buffer
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group_id,
    pattern = tmpfile,
    callback = function()
      log.debug("Archivo temporal cerrado: " .. tmpfile)

      -- Eliminar el archivo temporal después de procesar
      pcall(function() os.remove(tmpfile) end)

      -- Mostrar mensaje informativo
      notify.info("Archivo de edición de PR cerrado")
    end
  })

  -- Abrir el archivo temporal para edición
  vim.cmd("edit " .. tmpfile)

  -- Éxito al iniciar el proceso
  return true
end

function M.preview_with_external_editor(description, update_title, callback)
  log.debug("Iniciando vista previa con buffer de Neovim")
  log.debug("Parámetros: update_title=" .. tostring(update_title) .. ", descripción longitud=" .. #description)
  log.debug("Stack de llamada: " .. debug.traceback())
  -- IMPORTANT: Esta función crea un buffer en Neovim para editar descripciones de PR
  -- No intenta usar un editor externo, sino que aprovecha el API de buffers de Neovim

  -- Verificar que la función no es llamada desde un evento de Neovim asíncrono
  -- que podría causar problemas al crear UI
  local options = require("copilotchatassist.options")
  local force_preview = options.get().copilot_force_preview
  local in_event = vim.in_fast_event()

  if in_event and not force_preview then
    log.error("Error crítico: preview_with_external_editor llamada desde un evento asíncrono")
    log.debug("Para forzar la vista previa incluso en eventos asincrónicos, establece copilot_force_preview=true")
    if callback then callback(false) end
    return false
  elseif in_event and force_preview then
    log.warn("preview_with_external_editor llamada desde un evento asíncrono, pero copilot_force_preview está activado")
    log.warn("Intentando crear buffer de vista previa de todos modos (puede causar errores)")
  end

  -- Verificar que description es válida
  if not description then
    log.error("Error: description es nil en preview_with_external_editor")
    if callback then callback(false) end
    return false
  end

  if type(description) ~= "string" then
    log.error("Error: description no es un string en preview_with_external_editor, es un " .. type(description))
    if callback then callback(false) end
    return false
  end

  -- Obtener título actual
  local cmd_title = 'gh pr view --json title --jq .title 2>/dev/null'
  log.debug("Ejecutando comando para obtener título PR: " .. cmd_title)

  local current_title = ""
  local handle_title = nil
  local cmd_success, cmd_err = pcall(function()
    handle_title = io.popen(cmd_title)
    current_title = handle_title and handle_title:read("*a") or ""
    if handle_title then handle_title:close() end
    current_title = current_title:gsub("%s+$", "")
  end)

  if not cmd_success then
    log.error("Error al ejecutar comando de título PR: " .. tostring(cmd_err))
    current_title = "PR Preview"
  end

  log.debug("Título actual obtenido: '" .. current_title .. "'")

  -- Verificar entorno de UI y restricciones
  log.debug("Verificando entorno UI: has('nvim')=" .. vim.fn.has('nvim') .. ", has('terminal')=" .. vim.fn.has('terminal'))
  log.debug("Modo UI: headless=" .. tostring(vim.g.headless == true) .. ", vscode=" .. tostring(vim.g.vscode == true))

  -- Verificar si la vista previa está desactivada explícitamente
  -- Verificar configuración para deshabilitar/forzar vista previa
  log.debug("Configuración copilot_disable_preview: " .. tostring(vim.g.copilot_disable_preview))
  log.debug("Configuración copilot_force_preview: " .. tostring(force_preview))
  if vim.g.copilot_disable_preview then
    log.debug("Vista previa desactivada globalmente, actualizando directamente")
    notify.info("Actualizando PR sin vista previa (desactivada)...")

    -- Actualizar directamente
    local update_success = M.update_pr_content(description, false)

    -- Actualizar título si es necesario
    if update_success and update_title then
      local branch = get_current_branch()
      local ticket = branch:match("^([A-Z]+%-%d+)")

      if ticket and not current_title:match("^" .. ticket) then
        local new_title = ticket .. ": " .. current_title:gsub("^[A-Z]+%-%d+[:; ]%s*", "")
        local title_cmd = string.format("gh pr edit --title '%s'", new_title)
        local title_result = os.execute(title_cmd)

        if title_result == 0 or title_result == true then
          log.info("Título del PR actualizado correctamente: " .. new_title)
        else
          log.error("Error al actualizar el título del PR")
        end
      end
    end

    if callback then callback(update_success) end
    return update_success
  end

  -- Usar el módulo de buffer para crear un buffer con vista previa
  local buffer_utils = nil
  local require_success, require_err = pcall(function()
    buffer_utils = require("copilotchatassist.utils.buffer")
  end)

  if not require_success then
    log.error("Error al cargar módulo buffer_utils: " .. tostring(require_err))
    notify.error("Error interno: No se pudo cargar el módulo de buffer")
    if callback then callback(false) end
    return false
  end

  log.debug("Módulo buffer_utils cargado correctamente: " .. tostring(buffer_utils ~= nil))
  log.debug("Funciones disponibles: " .. vim.inspect(buffer_utils))

  -- Título para el buffer de vista previa
  local preview_title = "PR Preview - " .. (current_title or "")
  log.debug("Título para buffer de vista previa: '" .. preview_title .. "'")

  -- Instrucciones de edición como comentarios al inicio del buffer
  local content_with_instructions = [[# INSTRUCCIONES
# 1. Edite la descripción del PR a continuación
# 2. Use <leader>s para guardar y aplicar los cambios
# 3. Use <leader>q para cancelar
# Las líneas que comienzan con # serán ignoradas en el resultado final

]]

  -- Agregar título como comentario
  content_with_instructions = content_with_instructions .. "# TÍTULO ACTUAL: " .. current_title .. "\n\n"

  -- Agregar la descripción a editar
  content_with_instructions = content_with_instructions .. description

  -- Usar la función de creación de buffer de vista previa
  log.debug("Intentando crear buffer de vista previa con título: " .. preview_title)

  -- Verificar si estamos en UI o headless
  if not vim.g.gui_running and vim.fn.has('nvim') == 1 and vim.fn.has('terminal') == 1 then
    log.debug("Entorno UI detectado: gui_running=" .. tostring(vim.g.gui_running) ..
              ", nvim=" .. vim.fn.has('nvim') .. ", terminal=" .. vim.fn.has('terminal'))
  else
    log.warn("Entorno puede no ser adecuado para UI: " .. vim.inspect({
      gui_running = vim.g.gui_running,
      nvim = vim.fn.has('nvim'),
      terminal = vim.fn.has('terminal')
    }))

    -- Determinar si debemos continuar a pesar de entorno posiblemente inadecuado
    -- Usar la opción centralizada en lugar de la variable global
    local force_continue = options.get().copilot_force_preview == true
    log.debug("Force continue a pesar de posible entorno inadecuado: " .. tostring(force_continue))

    if not force_continue then
      log.warn("Cancelando creación de vista previa debido a entorno inadecuado")
      notify.warn("Entorno no ideal para vista previa, actualizando directamente")

      -- Actualizar directamente
      local update_success = M.update_pr_content(description, false)
      if callback then callback(update_success) end
      return update_success
    end
  end

  -- Verificar si create_preview_buffer existe y es una función
  if not buffer_utils.create_preview_buffer or type(buffer_utils.create_preview_buffer) ~= "function" then
    log.error("Error: la función create_preview_buffer no está disponible")
    notify.error("Error interno: función de vista previa no disponible")

    -- Actualizar directamente como fallback
    local update_success = M.update_pr_content(description, false)
    if callback then callback(update_success) end
    return update_success
  end

  local success, result = pcall(function()
    log.debug("Iniciando llamada a buffer_utils.create_preview_buffer")
    log.debug("Parámetros para create_preview_buffer:")
    log.debug("- preview_title: '" .. preview_title .. "'")
    log.debug("- content_with_instructions longitud: " .. #content_with_instructions .. " bytes")

    local buffer_created, window_id = nil, nil

    -- Usar un pcall adicional para mayor detalle en errores
    local call_success, call_result = pcall(function()
      buffer_created, window_id = buffer_utils.create_preview_buffer(
        preview_title,
        content_with_instructions,
        -- Callback al guardar
        function(edited_content)
          log.debug("Callback de guardado invocado, contenido recibido longitud: " ..
                    (edited_content and #edited_content or 0))

          -- Eliminar líneas de comentarios/instrucciones
          local lines = vim.split(edited_content, "\n")
          local clean_content = {}
          local in_content = false

          for _, line in ipairs(lines) do
            -- Si la línea comienza con # es un comentario/instrucción
            if not line:match("^#") then
              table.insert(clean_content, line)
              in_content = true
            elseif in_content then
              -- Si ya habíamos empezado a recopilar contenido y volvemos a encontrar un comentario,
              -- lo tratamos como parte del contenido (podría ser un comentario markdown)
              table.insert(clean_content, line)
            end
          end

          -- Reconstruir contenido sin líneas de instrucción
          local final_content = table.concat(clean_content, "\n")
          log.debug("Contenido procesado, longitud final: " .. #final_content)

          -- Actualizar el PR con el contenido editado
          log.debug("Invocando update_pr_content desde callback de guardar")
          local update_success = M.update_pr_content(final_content, false)

        -- Actualizar título si es necesario y la actualización fue exitosa
        if update_success and update_title then
          local branch = get_current_branch()
          local ticket = branch:match("^([A-Z]+%-%d+)")

          if ticket and not current_title:match("^" .. ticket) then
            local new_title = ticket .. ": " .. current_title:gsub("^[A-Z]+%-%d+[:; ]%s*", "")
            local title_cmd = string.format("gh pr edit --title '%s'", new_title)
            local title_result = os.execute(title_cmd)

            if title_result == 0 or title_result == true then
              log.info("Título del PR actualizado correctamente: " .. new_title)
            else
              log.error("Error al actualizar el título del PR")
            end
          end
        end

        -- Llamar al callback con el resultado
        if callback then
          callback(update_success)
        end
      end,
      -- Callback al cancelar
      function()
        log.info("Operación cancelada por el usuario")
        notify.info("Actualización de PR cancelada")

        if callback then
          callback(false)
        end
      end
    )

    return buffer_created, window_id
  end)

    -- Si hubo error en el pcall interno, capturar detalles
    if not call_success then
      log.error("Error interno en create_preview_buffer: " .. tostring(call_result))
      error("Error interno en create_preview_buffer: " .. tostring(call_result))
    end

    -- Verificar resultados de create_preview_buffer
    log.debug("Resultado de create_preview_buffer: buffer=" .. tostring(buffer_created) ..
              ", window=" .. tostring(window_id))

    if not buffer_created or not window_id then
      log.error("create_preview_buffer retornó valores inválidos: buffer=" ..
                tostring(buffer_created) .. ", window=" .. tostring(window_id))
      error("create_preview_buffer retornó valores inválidos")
    end

    -- Verificar que el buffer y la ventana son válidos
    local is_buffer_valid = vim.api.nvim_buf_is_valid(buffer_created)
    local is_window_valid = vim.api.nvim_win_is_valid(window_id)

    log.debug("Validación de resultados: buffer válido=" .. tostring(is_buffer_valid) ..
              ", ventana válida=" .. tostring(is_window_valid))

    if not is_buffer_valid or not is_window_valid then
      log.error("Buffer o ventana creados no son válidos")
      error("Buffer o ventana creados no son válidos")
    end

    return buffer_created, window_id
  end)

  -- Si hubo error creando el buffer, actualizar directamente
  if not success or not result then
    log.error("Error al crear vista previa: " .. tostring(result))

    -- Intentar obtener más información sobre el error
    local error_info = ""
    if type(result) == "string" then
      error_info = result
    elseif type(result) == "table" then
      error_info = vim.inspect(result)
    end

    log.error("Detalles del error de vista previa: " .. error_info)

    -- Capturar información adicional del stack
    if debug.traceback then
      log.error("Stack trace del error: " .. debug.traceback())
    end

    -- Verificar si buffer_utils está disponible
    local buffer_check = pcall(require, "copilotchatassist.utils.buffer")
    log.debug("Verificación de módulo buffer_utils: " .. tostring(buffer_check))

    -- Verificar estado del entorno Neovim
    local nvim_version = vim.version()
    log.debug("Versión de Neovim: " .. nvim_version.major .. "." .. nvim_version.minor .. "." .. nvim_version.patch)

    -- Intentar obtener información sobre el modo de Neovim
    log.debug("Modo de operación: modo_GUI=" .. tostring(vim.fn.has('gui_running') == 1) ..
              ", modo_terminal=" .. tostring(vim.fn.has('terminal') == 1))

    -- Notificar al usuario
    notify.warn("No se pudo crear vista previa, actualizando directamente")

    -- Actualizar directamente
    local update_success = M.update_pr_content(description, false)

    -- Actualizar título si es necesario
    if update_success and update_title then
      local branch = get_current_branch()
      local ticket = branch:match("^([A-Z]+%-%d+)")

      if ticket and not current_title:match("^" .. ticket) then
        local new_title = ticket .. ": " .. current_title:gsub("^[A-Z]+%-%d+[:; ]%s*", "")
        local title_cmd = string.format("gh pr edit --title '%s'", new_title)
        local title_result = os.execute(title_cmd)

        if title_result == 0 or title_result == true then
          log.info("Título del PR actualizado correctamente: " .. new_title)
        else
          log.error("Error al actualizar el título del PR")
        end
      end
    end

    if callback then callback(update_success) end
    return update_success
  end

  -- Si llegamos aquí, se ha creado el buffer de vista previa correctamente
  log.info("Buffer de vista previa creado exitosamente")

  -- Programar una verificación para asegurarnos de que el buffer sigue abierto
  local check_timer = vim.defer_fn(function()
    -- Intentar obtener una lista de buffers actuales
    local buffers = {}
    local buffer_check_success, buffer_check_err = pcall(function()
      buffers = vim.api.nvim_list_bufs()
    end)

    if not buffer_check_success then
      log.error("Error al verificar buffers: " .. tostring(buffer_check_err))
      return
    end

    local buffer_count = #buffers
    log.debug("Verificando estado de buffers después de crear preview. Buffers activos: " .. buffer_count)

    -- Listar todos los buffers para diagnóstico
    log.debug("Lista de buffers activos:")
    for i, buf in ipairs(buffers) do
      local buf_name = "[desconocido]"
      pcall(function() buf_name = vim.api.nvim_buf_get_name(buf) end)
      log.debug("  Buffer " .. i .. ": ID=" .. buf .. ", nombre='" .. buf_name .. "'")
    end

    -- Intentar verificar si hay ventanas flotantes activas
    local float_wins = {}
    local wins_check_success, wins_check_err = pcall(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config and config.relative and config.relative ~= "" then
          table.insert(float_wins, win)
        end
      end
    end)

    if not wins_check_success then
      log.error("Error al verificar ventanas: " .. tostring(wins_check_err))
      return
    end

    log.debug("Ventanas flotantes activas: " .. #float_wins)

    -- Listar todas las ventanas flotantes para diagnóstico
    if #float_wins > 0 then
      log.debug("Lista de ventanas flotantes activas:")
      for i, win in ipairs(float_wins) do
        local win_buf = "[desconocido]"
        pcall(function() win_buf = vim.api.nvim_win_get_buf(win) end)
        log.debug("  Ventana " .. i .. ": ID=" .. win .. ", buffer=" .. win_buf)
      end
    else
      log.warn("No se encontraron ventanas flotantes activas después de crear la vista previa")
    end

  end, 500)

  -- Registrar una verificación adicional más tardía
  vim.defer_fn(function()
    log.debug("Verificación secundaria de estado de vista previa (1000ms después)")
    local success, err = pcall(function()
      local cur_buf = vim.api.nvim_get_current_buf()
      local cur_win = vim.api.nvim_get_current_win()
      log.debug("Buffer actual: " .. cur_buf .. ", Ventana actual: " .. cur_win)
    end)

    if not success then
      log.error("Error en verificación secundaria: " .. tostring(err))
    end
  end, 1000)

  return true
end

-- ESTE CÓDIGO YA NO SE EJECUTA, SE HA DESACTIVADO LA VISTA PREVIA
-- El código comentado a continuación era parte de la implementación original
--[[
local function ejemplo_editor_externo(tmpfile)
  -- Comando para abrir editor (EVITANDO USAR NEOVIM/VIM)
  local cmd
  if vim.fn.has("mac") == 1 then
    -- En Mac, usamos TextEdit a través de 'open'
    cmd = "open -e " .. tmpfile
    log.debug("Usando open -e para abrir TextEdit en macOS")
  elseif vim.fn.has("unix") == 1 then
    -- En Linux, tratamos de usar un editor gráfico o nano como fallback
    local possible_editors = {"gedit", "kate", "pluma", "mousepad", "leafpad", "nano"}
    local editor_found = false

    for _, editor in ipairs(possible_editors) do
      if vim.fn.executable(editor) == 1 then
        cmd = editor .. " " .. tmpfile
        editor_found = true
        log.debug("Editor encontrado: " .. editor)
        break
      end
    end

    if not editor_found then
      cmd = "nano " .. tmpfile  -- Último recurso
      log.debug("Usando nano como editor predeterminado")
    end
  else
    -- Windows
    cmd = "notepad " .. tmpfile
  end
  return cmd
end
]]--

function M.force_reset_pr_operations()
  log.info("Forzando reset de operaciones de PR")
  M.pr_generation_in_progress = false
  M.pr_update_in_progress = false
  M.pr_operation_id = nil
  M.pr_update_completed = false

  notify.info("Estado de operaciones de PR reseteado")
end

-- Nueva función ultra simple para actualizar el título del PR directamente con gh
function M.direct_update_pr_title(title)
  if not title or title == "" then
    log.error("No se puede actualizar el título del PR: título vacío")
    notify.error("Título vacío, no se puede actualizar")
    return false
  end

  log.info("⚠️ ACTUALIZANDO TÍTULO DEL PR: '" .. tostring(title) .. "'")
  vim.api.nvim_echo({{"⚠️ ACTUALIZANDO TÍTULO PR: " .. tostring(title), "WarningMsg"}}, true, {})

  -- Guardar en archivo de log dedicado para diagnóstico
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")
  local log_file = debug_dir .. "/title_update_debug.txt"
  local log_f = io.open(log_file, "a")
  if log_f then
    log_f:write("\n----- " .. os.date("%Y-%m-%d %H:%M:%S") .. " -----\n")
    log_f:write("Intentando actualizar título: '" .. tostring(title) .. "'\n")
    log_f:write("Stack trace: " .. debug.traceback() .. "\n")
    log_f:close()
  end

  -- Obtener PR number para diagnóstico
  local pr_number = nil
  local pr_check_cmd = "gh pr view --json number --jq .number 2>/dev/null"
  local handle_pr = io.popen(pr_check_cmd)
  if handle_pr then
    pr_number = handle_pr:read("*a"):gsub("%s+$", "")
    handle_pr:close()
    log.debug("PR number detectado: " .. pr_number)
  end

  -- Método DIRECTO PARA ACTUALIZAR EL TÍTULO CON NÚMERO DE PR ESPECÍFICO
  -- Este método es el más confiable y lo intentamos primero
  if pr_number and pr_number ~= "" then
    log.info("⚠️ USANDO MÉTODO DIRECTO CON NÚMERO DE PR: " .. pr_number)
    vim.api.nvim_echo({{"⚠️ ACTUALIZANDO TÍTULO PR " .. pr_number, "WarningMsg"}}, true, {})

    -- Guardar el título en un archivo para diagnóstico
    local title_file = debug_dir .. "/title_to_update_" .. os.time() .. ".txt"
    local tf = io.open(title_file, "w")
    if tf then
      tf:write(title)
      tf:close()
    end

    -- Usar gh pr edit con número de PR y título como parámetro directo
    local escaped_title = title:gsub("'", "'\\''")
    local cmd = string.format("gh pr edit %s --title '%s' 2>&1", pr_number, escaped_title)
    log.debug("Ejecutando comando: " .. cmd)

    -- Capturar salida para diagnóstico
    local handle = io.popen(cmd)
    local result_output = handle and handle:read("*a") or ""
    local exit_code = handle and handle:close() or 1

    -- Guardar la salida para diagnóstico
    if log_f then
      log_f = io.open(log_file, "a")
      log_f:write("Método con PR number específico\n")
      log_f:write("Comando: " .. cmd .. "\n")
      log_f:write("Salida: " .. result_output .. "\n")
      log_f:write("Código de salida: " .. tostring(exit_code) .. "\n")
      log_f:close()
    end

    if exit_code == true or exit_code == 0 then
      log.info("✅ TÍTULO DEL PR #" .. pr_number .. " ACTUALIZADO: '" .. title .. "'")
      vim.api.nvim_echo({{"✅ TÍTULO PR #" .. pr_number .. " ACTUALIZADO: " .. title, "String"}}, true, {})
      notify.success("Título del PR actualizado correctamente")
      return true
    else
      log.warn("Fallo en método directo con PR number, intentando métodos alternativos")
    end
  end

  -- Crear un archivo temporal con el título (evita problemas de escape)
  local tmpfile = "/tmp/pr_title_direct_" .. os.time() .. ".txt"
  local tmp_f = io.open(tmpfile, "w")
  if not tmp_f then
    log.error("No se pudo crear archivo temporal para título")
    notify.error("Error al crear archivo temporal")
    return false
  end

  tmp_f:write(title)
  tmp_f:close()

  -- Usar gh pr edit con título desde archivo
  log.debug("Ejecutando actualización directa del título con archivo: " .. tmpfile)
  local cmd = string.format("gh pr edit --title-file '%s' 2>&1", tmpfile)

  -- Capturar también stderr para diagnóstico
  local handle = io.popen(cmd)
  local result_output = handle and handle:read("*a") or ""
  local exit_code = handle and handle:close() or 1

  -- Guardar la salida para diagnóstico
  if log_f then
    log_f = io.open(log_file, "a")
    log_f:write("Comando: " .. cmd .. "\n")
    log_f:write("Salida: " .. result_output .. "\n")
    log_f:write("Código de salida: " .. tostring(exit_code) .. "\n")
    log_f:close()
  end

  if exit_code == true or exit_code == 0 then
    log.info("✅ TÍTULO DEL PR ACTUALIZADO CON MÉTODO DIRECTO: '" .. title .. "'")
    vim.api.nvim_echo({{"✅ TÍTULO PR ACTUALIZADO: " .. title, "String"}}, true, {})
    notify.success("Título del PR actualizado correctamente")
    os.remove(tmpfile)
    return true
  end

  -- Método alternativo si falla
  log.warn("Método con archivo falló, intentando con título como parámetro")
  local escaped_title = title:gsub("'", "'\\''")
  cmd = string.format("gh pr edit --title '%s' 2>&1", escaped_title)

  -- Capturar también stderr para diagnóstico
  handle = io.popen(cmd)
  result_output = handle and handle:read("*a") or ""
  exit_code = handle and handle:close() or 1

  -- Guardar la salida para diagnóstico
  if log_f then
    log_f = io.open(log_file, "a")
    log_f:write("Método alternativo\n")
    log_f:write("Comando: " .. cmd .. "\n")
    log_f:write("Salida: " .. result_output .. "\n")
    log_f:write("Código de salida: " .. tostring(exit_code) .. "\n")
    log_f:close()
  end

  if exit_code == true or exit_code == 0 then
    log.info("✅ TÍTULO DEL PR ACTUALIZADO CON MÉTODO ALTERNATIVO: '" .. title .. "'")
    vim.api.nvim_echo({{"✅ TÍTULO PR ACTUALIZADO: " .. title, "String"}}, true, {})
    notify.success("Título del PR actualizado correctamente")
    os.remove(tmpfile)
    return true
  end

  log.error("❌ NO SE PUDO ACTUALIZAR EL TÍTULO DEL PR: '" .. title .. "'")
  vim.api.nvim_echo({{"❌ ERROR AL ACTUALIZAR TÍTULO PR: " .. title, "ErrorMsg"}}, true, {})
  notify.error("No se pudo actualizar el título del PR")
  os.remove(tmpfile)
  return false
end

-- Variable global para almacenar el último título sugerido
M.last_suggested_title = nil

-- Estructura para almacenar títulos alternativos para esta sesión
M.alternative_titles = {}

-- Función para sugerir un título alternativo basado en el contenido actual del PR
function M.suggest_alternative_title(direct_add)
  local notify = require("copilotchatassist.utils.notify")
  local progress = require("copilotchatassist.utils.progress")
  local options = require("copilotchatassist.options")

  -- Inicializar direct_add si no se proporciona
  direct_add = direct_add or false

  -- Obtener el diff actual
  get_diff(function(diff)
    if not diff or diff == "" then
      notify.error("No se encontraron cambios para generar un título alternativo")
      return
    end

    -- Obtener la descripción actual del PR
    M.get_pr_description(function(description)
      if not description or description == "" then
        notify.error("No se encontró descripción del PR para analizar")
        return
      end

      -- Iniciar spinner
      progress.start_spinner("generate_alt_title", "Generando título alternativo...")

      -- Siempre usar el idioma específico para PR o el configurado
      local language = options.get().pr_language or options.get().language
      log.debug("Usando idioma para título alternativo: " .. language)

      -- Crear prompt para generar título alternativo basado en diff y descripción
      local prompt
      if language == "spanish" then
        prompt = string.format([[
        Eres un experto en crear títulos descriptivos para Pull Requests.

        Basado en el diff y la descripción proporcionados, genera un título alternativo para este PR.

        El título debe:
        - Ser conciso (menos de 70 caracteres sin contar el ticket)
        - Capturar la esencia de los cambios
        - Utilizar verbos en presente (ej: "Añade", "Corrige", "Mejora")
        - No incluir número de ticket
        - Estar escrito en español

        Proporciona ÚNICAMENTE el título sugerido, sin explicaciones ni comentarios adicionales.

        === DIFF ===
        %s

        === DESCRIPCIÓN ACTUAL ===
        %s
        ]], diff:sub(1, 3000), description:sub(1, 3000))
      else
        prompt = string.format([[
        You're an expert at creating descriptive Pull Request titles.

        Based on the provided diff and description, generate an alternative title for this PR.

        The title should:
        - Be concise (less than 70 characters without counting the ticket)
        - Capture the essence of the changes
        - Use present tense verbs (e.g., "Add", "Fix", "Improve")
        - Not include any ticket number
        - Be written in English

        Provide ONLY the suggested title, without any explanations or additional comments.

        === DIFF ===
        %s

        === CURRENT DESCRIPTION ===
        %s
        ]], diff:sub(1, 3000), description:sub(1, 3000))
      end

      -- Generar título alternativo con CopilotChat
      copilot_api.ask(prompt, {
        callback = function(response)
          -- Detener spinner
          progress.stop_spinner("generate_alt_title", true)

          if not response or response == "" then
            notify.error("No se pudo generar un título alternativo")
            return
          end

          -- Limpiar la respuesta (solo necesitamos el título)
          local title = response:match("^%s*(.-)%s*$")

          -- Mostrar el título generado
          local branch = get_current_branch()
          local ticket = branch:match("^([A-Z]+%-%d+)")

          -- Guardar el título generado para uso posterior
          M.last_suggested_title = title

          -- Añadir a la lista de títulos alternativos
          if not vim.tbl_contains(M.alternative_titles, title) then
            table.insert(M.alternative_titles, title)
          end

          -- Formatear título con ticket si existe
          local full_title = ticket and (ticket .. ": " .. title) or title

          -- Mostrar título sugerido en notificación
          notify.info("Título sugerido: " .. full_title, {timeout = 10000})

          if direct_add then
            -- Agregar directamente al buffer
            M.add_suggested_title_to_buffer(title)
          else
            -- Preguntar si desea aplicar o añadir como alternativa
            vim.defer_fn(function()
              vim.ui.select({
                "Añadir como alternativa al archivo",
                "Reemplazar título actual",
                "Descartar"
              }, {
                prompt = "¿Qué desea hacer con el título sugerido?",
              }, function(choice)
                if choice == "Añadir como alternativa al archivo" then
                  -- Añadir al buffer como alternativa
                  M.add_suggested_title_to_buffer(title, true)
                elseif choice == "Reemplazar título actual" then
                  -- Reemplazar el título actual
                  M.add_suggested_title_to_buffer(title, false, true)
                end
              end)
            end, 500)
          end
        end,
        system_prompt = "Eres un experto en generar títulos concisos y descriptivos para Pull Requests basados en el código y contexto.",
        temperature = 0.3, -- Temperatura baja para títulos más precisos
        timeout = 15000 -- 15 segundos máximo
      })
    end)
  end)
end

-- Función para agregar el título sugerido al buffer
function M.add_suggested_title_to_buffer(title, as_alternative, replace_current)
  -- Valores predeterminados
  as_alternative = as_alternative or false
  replace_current = replace_current or false

  local notify = require("copilotchatassist.utils.notify")

  -- Buscar el buffer temporal de edición de PR
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("/tmp/copilot_pr_.*%.md$") then
      -- Obtener las líneas del buffer
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local title_marker_start_idx = nil
      local title_marker_end_idx = nil
      local title_line_idx = nil
      local current_title = nil

      -- Buscar la sección de título y el título actual
      for i, line in ipairs(lines) do
        if line:match("^# <pr_title_marker>") then
          title_marker_start_idx = i
        elseif line:match("^# </pr_title_marker>") then
          title_marker_end_idx = i
        elseif line:match("<pr_title>.*</pr_title>") then
          title_line_idx = i
          current_title = line:match("<pr_title>(.*)</pr_title>")
        end
      end

      -- Si encontramos la sección de título
      if title_marker_start_idx and title_marker_end_idx and title_line_idx then
        if replace_current then
          -- Reemplazar el título actual
          local new_line = lines[title_line_idx]:gsub("<pr_title>.*</pr_title>", "<pr_title>" .. title .. "</pr_title>")
          vim.api.nvim_buf_set_lines(buf, title_line_idx-1, title_line_idx, false, {new_line})
          notify.success("Título actual reemplazado. Guarde para actualizar el PR.")
        elseif as_alternative then
          -- Añadir como alternativa después del título actual
          local alternativa_line = "# <pr_alt_title>" .. title .. "</pr_alt_title> (Alternativo)"

          -- Verificar si ya existe esta alternativa
          local already_exists = false
          for i = title_marker_start_idx, title_marker_end_idx do
            if lines[i]:match("<pr_alt_title>" .. title .. "</pr_alt_title>") then
              already_exists = true
              break
            end
          end

          if not already_exists then
            -- Insertar justo antes del marcador de cierre
            vim.api.nvim_buf_set_lines(buf, title_marker_end_idx-1, title_marker_end_idx-1, false, {alternativa_line})
            notify.success("Título alternativo añadido. Edite y guarde para actualizar.")
          else
            notify.info("Este título alternativo ya existe en el buffer.")
          end
        else
          -- Reemplazar el título actual por defecto
          local new_line = lines[title_line_idx]:gsub("<pr_title>.*</pr_title>", "<pr_title>" .. title .. "</pr_title>")
          vim.api.nvim_buf_set_lines(buf, title_line_idx-1, title_line_idx, false, {new_line})
          notify.success("Título alternativo aplicado. Guarde para actualizar el PR.")
        end

        -- Salir del loop una vez encontrado
        break
      else
        notify.error("No se pudo encontrar la sección de título en el buffer")
      end
    end
  end
end

-- Función principal de mejora de PR, que maneja opciones y coordina el flujo
function M.enhance_pr(opts)
  -- Evitar operaciones concurrentes
  if M.pr_generation_in_progress or M.pr_update_in_progress then
    log.warn("Ya hay una operación de PR en curso")
    notify.warn("Ya hay una operación de PR en curso, espere a que termine")
    return
  end

  -- Limpiar notificaciones existentes
  notify.clear()

  -- Indicar que hay una operación en curso
  local operation_id = tostring(os.time()) .. "_" .. math.random(1000, 9999)
  log.debug("Iniciando operación PR con ID: " .. operation_id)

  -- Detectar el ticket de Jira en la rama
  local branch = get_current_branch()
  local ticket = branch:match("^([A-Z]+%-%d+)")
  if ticket then
    log.debug("Detectado ticket de Jira en rama: " .. ticket)
  end

  -- Verificar si hay un PR existente
  M.get_pr_data(function(pr_data)
    if pr_data then
      log.debug("PR encontrado: " .. vim.inspect({
        number = pr_data.number,
        state = pr_data.state,
        isDraft = pr_data.isDraft
      }))

      notify.info("Comenzando la mejora de la descripción del PR. Esto puede tomar un momento...")

      -- Obtener el idioma a usar
      local language = require("copilotchatassist.options").get().pr_language or require("copilotchatassist.options").get().language
      log.debug("Idioma configurado para PR: " .. language)

      -- Obtener descripción actual del PR
      M.get_pr_description(function(description)
        if description and description ~= "" then
          -- Verificar si es un template básico o una descripción completa
          if M.has_template_description then
            log.info("Se detectó un template como descripción. Se marcará para enriquecimiento.")

            -- Generar descripción a partir del template
            log.info("Generando descripción a partir de template")
            M.generate_pr_description(function(new_description)
              if new_description then
                -- Si se generó un título automáticamente, usarlo
                if M.last_suggested_title and M.last_suggested_title ~= "" then
                  log.info("Usando título generado automáticamente: " .. M.last_suggested_title)
                  notify.info("Título generado automáticamente: " .. M.last_suggested_title)
                end

                -- Actualizar PR con la nueva descripción
                M.update_pr_with_preview(new_description, opts.update_title, opts.use_preview)
              else
                notify.error("No se pudo generar una descripción para el PR")
              end
            end)
          else
            log.debug("PR tiene una descripción completa, procediendo con enhancement normal")

            -- Obtener diff
            get_diff(function(diff)
              if not diff then
                log.error("No se pudo obtener el diff para mejorar la descripción")
                notify.error("No se pudo obtener el diff para mejorar la descripción")
                return
              end

              -- Detectar idioma en la descripción existente
              local sample_text = description:sub(1, 1000)
              log.debug("Texto demasiado largo, analizando una muestra de 1000 caracteres")
              local spanish_count = select(2, sample_text:gsub("[áéíóúñÁÉÍÓÚÑ]", ""))
              local english_count = select(2, sample_text:gsub("\\bthe\\b|\\band\\b|\\bwith\\b|\\bfor\\b", ""))
              log.debug("Detección de idioma - Español: " .. spanish_count .. ", Inglés: " .. english_count)

              local detected_language = "english"
              if spanish_count > english_count then
                detected_language = "spanish"
              end

              log.info("Idioma detectado en la descripción del PR: " .. detected_language)
              log.info("Idioma configurado para usar: " .. language)

              log.debug("IMPORTANTE: Usando el idioma configurado (" .. language .. ") para la generación del PR")

              -- Mejorar la descripción con CopilotChat
              log.debug("Enhancing PR description with CopilotChat...")

              -- Iniciar actualización del PR
              M.pr_update_in_progress = true

              -- Enviar solicitud para mejorar el PR
              M.pr_operation_id = operation_id
              log.debug("PR update in progress flag before sending request: " .. tostring(M.pr_update_in_progress))
              log.debug("Enviando solicitud de PR enhancement con operation_id: " .. operation_id)

              local prompt = ""
              if language == "spanish" then
                prompt = string.format([[Eres un experto en mejorar descripciones de Pull Requests.
                Mejora la siguiente descripción de PR manteniendo la estructura y el idioma existentes.
                Haz que sea más clara, completa y profesional, pero no cambies radicalmente el contenido o intención.
                Si hay diagramas o visualizaciones, asegúrate de mantenerlos y mejorarlos si es necesario.
                Sé específico sobre los cambios realizados basados en el diff proporcionado.
                Conserva el formato markdown existente.
                Responde con la descripción mejorada completa, sin comentarios adicionales.

                Descripción actual:
                %s

                Diff de cambios:
                %s
                ]], description, diff)
              else
                prompt = string.format([[You're an expert at enhancing Pull Request descriptions.
                Improve the following PR description while maintaining the existing structure and language.
                Make it clearer, more complete, and more professional, but don't radically change the content or intent.
                If there are any diagrams or visualizations, make sure to maintain them and improve them if necessary.
                Be specific about the changes made based on the provided diff.
                Preserve the existing markdown format.
                Respond with the complete enhanced description, without additional comments.

                Current description:
                %s

                Changes diff:
                %s
                ]], description, diff)
              end

              -- Enviar a CopilotChat
              log.debug("Enviando solicitud a CopilotChat con callback único")
              copilot_api.ask(prompt, {
                callback = function(response)
                  -- Manejar la respuesta
                  if M.pr_operation_id ~= operation_id then
                    log.debug("Operación cancelada o reemplazada")
                    return
                  end

                  -- Actualizar con vista previa si se especificó
                  -- Asegurar que update_title sea true para permitir la actualización de títulos
                  local update_title = opts.update_title
                  if update_title == nil then
                    update_title = true  -- Por defecto, permitir actualización de título
                  end
                  log.debug("Actualizando PR con update_title=" .. tostring(update_title))

                  -- Extraer título de la respuesta si existe
                  local extracted_title = nil
                  if type(response) == "string" then
                    extracted_title = response:match("<pr_title>(.-)</pr_title>")
                    if extracted_title then
                      log.info("Título encontrado en la respuesta: " .. extracted_title)
                      M.last_suggested_title = extracted_title
                      notify.info("Título sugerido: " .. extracted_title)
                    end
                  end

                  -- Asegurar que el título se actualice
                  log.debug("Actualizando PR con update_title=" .. tostring(update_title))
                  M.ultra_direct_update(response, true, opts.use_preview)
                end
              })

              -- Verificar si es necesario actualizar el título del PR
              if opts.update_title and ticket then
                log.info("Verificando si es necesario actualizar título del PR con ticket: " .. ticket)
                M.update_pr_title_with_jira_ticket()
              end
            end)
          end
        else
          -- No hay descripción existente, generar una nueva
          log.info("No hay descripción existente, generando una nueva desde cero")

          M.generate_pr_description(function(new_description)
            if new_description then
              -- Actualizar PR con la nueva descripción
              M.update_pr_with_preview(new_description, opts.update_title, opts.use_preview)
            else
              notify.error("No se pudo generar una descripción para el PR")
            end
          end)
        end
      end)
    else
      notify.error("No se encontró un PR para esta rama")
    end
  end)
end

return M