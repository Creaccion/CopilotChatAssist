-- Módulo para generar y mejorar PRs con soporte multi-idioma
local M = {}

local log = require("copilotchatassist.utils.log")
local file_utils = require("copilotchatassist.utils.file")
local copilot_api = require("copilotchatassist.copilotchat_api")
local i18n = require("copilotchatassist.i18n")
local notify = require("copilotchatassist.utils.notify")

-- Estado del módulo
M.state = {
  current_pr = nil,  -- Almacena información del PR actual
  pr_language = nil  -- Idioma detectado del PR
}

-- Idiomas soportados para la generación de PRs
M.supported_languages = {
  english = true,
  spanish = true
}

-- Obtiene la descripción del PR actual desde GitHub usando gh CLI
local function get_pr_description()
  local handle = io.popen('gh pr view --json body --jq .body 2>/dev/null')
  local desc = handle:read("*a")
  handle:close()
  if desc == "" or desc:match("not found") then
    return nil
  end
  return desc
end

-- Obtiene el nombre de la rama por defecto
local function get_default_branch()
  local handle = io.popen("git remote show origin | grep 'HEAD branch' | awk '{print $3}'")
  local branch = handle:read("*a")
  handle:close()
  branch = branch and branch:gsub("%s+", "")
  if branch == "" then
    branch = "main"
  end
  return branch
end

-- Obtiene los cambios entre la rama actual y la rama base (limitando el tamaño para evitar problemas)
local function get_diff()
  local default_branch = get_default_branch()
  local cmd = string.format("git diff origin/%s...HEAD", default_branch)
  local handle = io.popen(cmd)
  local diff = handle:read("*a")
  handle:close()

  -- Limitar el tamaño del diff para evitar problemas con CopilotChat
  local max_diff_size = 10000 -- caracteres
  if diff and #diff > max_diff_size then
    log.info(string.format("Truncando diff de %d caracteres a %d caracteres", #diff, max_diff_size))
    diff = diff:sub(1, max_diff_size) .. "\n\n... [diff truncado debido a su tamaño] ...\n"
  end

  return diff
end

-- Actualiza la descripción del PR
local function update_pr_description(new_desc)
  -- Imprimir detalles de depuración
  log.debug("Actualizando descripción del PR")

  -- Manejar diferentes tipos de respuesta (string o tabla con campo content)
  local desc_content = new_desc

  -- Si es una tabla, intentar extraer el campo content
  if type(new_desc) == "table" then
    log.debug("La descripción es una tabla, intentando extraer el campo content")
    if new_desc.content and type(new_desc.content) == "string" then
      desc_content = new_desc.content
      log.debug("Extraído campo content de la tabla correctamente")
    else
      log.error("La descripción es una tabla pero no tiene un campo content válido")
      log.debug("Estructura de la tabla: " .. vim.inspect(new_desc))
      return false
    end
  elseif type(new_desc) ~= "string" then
    log.error("La descripción no es ni string ni tabla: " .. type(new_desc))
    return false
  end

  -- Verificar que tenemos un string válido
  if not desc_content or desc_content == "" then
    log.error("Contenido de descripción vacío o inválido")
    return false
  end

  -- Limitar el tamaño de la descripción para evitar problemas con GitHub
  local max_description_size = 60000 -- Límite seguro para PR de GitHub (en caracteres)
  if #desc_content > max_description_size then
    log.warn(string.format("La descripción del PR es demasiado larga (%d caracteres). Truncando a %d caracteres.",
                          #desc_content, max_description_size))
    desc_content = desc_content:sub(1, max_description_size - 100) ..
                  "\n\n---\n\n⚠️ *Esta descripción ha sido truncada debido a su longitud*\n"
  end

  log.debug("Longitud de la nueva descripción: " .. tostring(#desc_content) .. " caracteres")

  -- Usar una ruta temporal única para evitar conflictos
  local tmpfile = os.tmpname()
  log.debug("Usando archivo temporal: " .. tmpfile)

  -- Escribir contenido con manejo de errores
  local f, err = io.open(tmpfile, "w")
  if not f then
    log.error("Error al abrir el archivo temporal: " .. tostring(err))
    return false
  end

  -- Guardar el contenido para depuración
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")
  local debug_file = debug_dir .. "/pr_description_content.txt"
  local df = io.open(debug_file, "w")
  if df then
    df:write(desc_content)
    df:close()
    log.debug("Contenido de descripción guardado en " .. debug_file)
  end

  local write_success, write_err = f:write(desc_content)
  if not write_success then
    log.error("Error al escribir en el archivo temporal: " .. tostring(write_err))
    f:close()
    os.remove(tmpfile)
    return false
  end

  f:close()

  -- Update the PR using gh with better error handling
  local cmd = string.format("gh pr edit --body-file '%s' 2>&1", tmpfile)
  log.debug("Ejecutando comando: " .. cmd)

  local handle, cmd_err = io.popen(cmd)
  if not handle then
    log.error("Error al ejecutar gh pr edit: " .. tostring(cmd_err))
    os.remove(tmpfile)
    return false
  end

  local result = handle:read("*a")
  local close_status = handle:close()

  -- Limpiar archivo temporal
  os.remove(tmpfile)

  -- Verificar resultado
  if not close_status then
    log.error("Error al actualizar la descripción del PR. Salida del comando:")
    log.error(result)
    return false
  end

  -- Registrar información más detallada para depuración
  if result and result:match("No changes") then
    log.info("GitHub reporta que no hubo cambios en la descripción del PR")
    log.debug("Salida del comando: " .. result)
    return true
  elseif result and result:match("Updating pull request") then
    log.info("PR description updated successfully")
    log.debug("Salida del comando: " .. result)
    return true
  else
    log.info("PR description parece haberse actualizado")
    log.debug("Salida del comando: " .. result)
    return true
  end
end

-- Genera un título para el PR basado en los cambios
function M.generate_pr_title(callback)
  local diff = get_diff()
  if diff == "" then
    log.debug("No se encontraron cambios para generar un título")
    return
  end

  -- Always use the configured language from options
  local language = options.get().language
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
        if callback then
          callback(title)
        end
      else
        log.debug("Failed to generate PR title.")
        if callback then
          callback(nil)
        end
      end
    end
  })
end

-- Genera una descripción para el PR basada en los cambios
function M.generate_pr_description(callback)
  local diff = get_diff()
  if diff == "" then
    log.debug("No se encontraron cambios para generar una descripción")
    return
  end

  -- Always use the configured language from options
  local language = options.get().language
  local summary_section = i18n.t("pr.summary_section")
  local changes_section = i18n.t("pr.changes_section")
  local test_section = i18n.t("pr.test_section")
  local summary_bullet = i18n.t("pr.summary_bullet")
  local test_todo = i18n.t("pr.test_todo")

  local prompt
  if language == "spanish" then
    prompt = string.format([[
    Eres un asistente experto en documentación de Pull Requests.
    Genera una descripción completa y detallada para un Pull Request basada en los cambios proporcionados.

    INSTRUCCIONES IMPORTANTES:
    1. Respeta la estructura existente si detectas un patrón en la descripción actual.
    2. Si no hay estructura existente, organiza la descripción con las siguientes secciones:

    %s
    %s la funcionalidad que resuelve el problema principal
    - Explicación breve pero completa de la solución
    - Cualquier contexto adicional relevante

    %s
    - Lista de todos los cambios importantes realizados
    - Explicación de por qué se eligió esta implementación
    - Menciones de cualquier consideración de diseño

    %s
    %s la funcionalidad principal
    - Incluye casos de prueba específicos con ejemplos concretos
    - Menciona escenarios de borde que deberían probarse
    - Sugiere pruebas de regresión si es relevante

    3. SIEMPRE incluye diagramas en formato mermaid para:
       - Flujos de datos o procesos
       - Arquitectura de componentes
       - Relaciones entre módulos
       - Secuencias de interacción importantes

    4. Para los diagramas mermaid:
       - Usa colores y formas para mejorar la legibilidad
       - Incluye comentarios explicativos dentro del diagrama
       - Mantén la complejidad manejable (máximo 15-20 nodos por diagrama)
       - Si es necesario, divide en múltiples diagramas más específicos

    5. Si encuentras partes incompletas o ambiguas en el código:
       - Señálalas claramente en la descripción
       - Sugiere mejoras específicas

    6. Asegúrate de que la descripción sea coherente y detallada.

    La descripción final debe estar en español.

    Cambios:
    %s
    ]], summary_section, summary_bullet, changes_section, test_section, test_todo, diff)
  else
    prompt = string.format([[
    You're an expert assistant in Pull Request documentation.
    Generate a comprehensive and detailed description for a Pull Request based on the provided changes.

    IMPORTANT INSTRUCTIONS:
    1. Respect any existing structure if you detect a pattern in the current description.
    2. If no existing structure is present, organize the description with the following sections:

    %s
    %s the functionality that solves the main issue
    - Brief but complete explanation of the solution
    - Any relevant additional context

    %s
    - List of all important changes made
    - Explanation of why this implementation was chosen
    - Mentions of any design considerations

    %s
    %s the main functionality
    - Include specific test cases with concrete examples
    - Mention edge cases that should be tested
    - Suggest regression tests if relevant

    3. ALWAYS include mermaid diagrams for:
       - Data or process flows
       - Component architecture
       - Module relationships
       - Important interaction sequences

    4. For mermaid diagrams:
       - Use colors and shapes to improve readability
       - Include explanatory comments within the diagram
       - Keep complexity manageable (maximum 15-20 nodes per diagram)
       - If necessary, split into multiple more specific diagrams

    5. If you find incomplete or ambiguous parts in the code:
       - Clearly mark them in the description
       - Suggest specific improvements

    6. Ensure the description is coherent and detailed.

    The final description should be in English.

    Changes:
    %s
    ]], summary_section, summary_bullet, changes_section, test_section, test_todo, diff)
  end

  log.debug("Generating PR description with CopilotChat...")
  copilot_api.ask(prompt, {
    callback = function(response)
      local description = response or ""
      if description ~= "" then
        log.debug("PR description generated.")
        -- Guardar el idioma actual de la descripción
        M.state.pr_language = language
        if callback then
          callback(description)
        end
      else
        log.debug("Failed to generate PR description.")
        if callback then
          callback(nil)
        end
      end
    end
  })
end

-- Mejora una descripción de PR existente
function M.enhance_pr(opts)
  opts = opts or {}
  local old_desc = get_pr_description()

  -- Obtener la configuración de idioma del usuario
  local options = require("copilotchatassist.options")
  local target_language = options.get().language
  log.debug("Idioma configurado en opciones: " .. target_language)

  if not old_desc or old_desc == "" then
    log.debug("No PR description found. Generating a new one...")
    M.generate_pr_description(function(new_desc)
      if new_desc then
        update_pr_description(new_desc)
        -- Command completion - show at INFO level
        notify.success("PR description created.", {force = true})
      end
    end)
    return
  end

  local diff = get_diff()
  if diff == "" then
    log.debug("No se encontraron cambios recientes para mejorar la descripción")
    return
  end

  -- Detectar idioma de la descripción actual
  local detected_language = i18n.detect_language(old_desc)

  -- Mostrar información sobre la detección de idioma
  log.info("Idioma detectado en la descripción del PR: " .. detected_language)
  log.info("Idioma configurado para usar: " .. target_language)

  -- Crear identificador para notificación
  -- Utilizar el sistema de progreso visual para mostrar el avance
  local progress = require("copilotchatassist.utils.progress")
  local spinner_id = "enhance_pr"
  progress.start_spinner(spinner_id, "Enhancing PR description", {
    style = options.get().progress_indicator_style,
    position = "statusline"
  })

  -- Mantener también log para debug
  log.debug("Enhancing PR description with CopilotChat...")

  -- Configurar timeout con valor más alto para evitar problemas con PRs grandes
  local timeout_timer = vim.loop.new_timer()
  timeout_timer:start(300000, 0, vim.schedule_wrap(function()
    -- Si llegamos aquí, la solicitud nunca completó
    -- Detener el spinner
    progress.stop_spinner(spinner_id, false)

    log.warn("Timeout alcanzado. La operación tomó demasiado tiempo.")

    -- Detener y cerrar timer
    if timeout_timer then
      timeout_timer:stop()
      timeout_timer:close()
    end
  end)) -- 5 minutos de timeout para dar más tiempo a CopilotChat

  -- Crear un prompt simplificado con límite de tamaño para evitar respuestas excesivamente largas
  local prompt

  if detected_language ~= target_language then
    -- Si los idiomas son diferentes, incluir instrucciones de traducción
    prompt = string.format([[
    Eres un asistente experto en documentación y traducción de Pull Requests.

    INSTRUCCIONES PRINCIPALES:
    1. TRADUCE la descripción del PR del idioma %s al idioma %s.
    2. MEJORA la descripción mientras la traduces, analizando los cambios recientes.
    3. SE EXTREMADAMENTE CONCISO (máximo ~3000 caracteres).
    4. ENFOCATE SOLO en la información más importante.

    INSTRUCCIONES IMPORTANTES:
    - Usa puntos para listas y sé breve en cada punto
    - Evita detalles excesivos y explicaciones largas
    - Resume detalles de implementación en vez de explicarlos por completo
    - Devuelve SOLO la descripción final, sin comentarios ni texto adicional
    - Evita cualquier texto redundante o innecesario

    INSTRUCCIONES PARA DIAGRAMAS MERMAID:
    - Incluye UN SOLO diagrama mermaid SOLO SI es absolutamente necesario
    - Usa sintaxis simple y válida para evitar errores de parsing
    - Evita caracteres especiales en los textos de los nodos
    - Usa nombres cortos para los nodos (A, B, C...)
    - Siempre escapa los corchetes dentro del texto con \[ y \]
    - NO uses comillas dentro del texto de los nodos
    - Asegura que cada nodo tiene un cierre correcto
    - Si incluyes un nodo con caracteres especiales, usa comillas para todo el texto
    - Ejemplo correcto: A[Enviar datos] --> B[Procesar respuesta]

    Descripción actual (%s):
    %s

    Cambios recientes:
    %s
    ]],
    detected_language, target_language, detected_language, old_desc, diff)
  else
    -- Si el idioma es el mismo, solo mejorar la descripción
    if target_language == "spanish" then
      prompt = string.format([[
      Eres un asistente experto en documentación de Pull Requests.

      INSTRUCCIONES PRINCIPALES:
      1. MEJORA la descripción basándote en los cambios recientes.
      2. SE EXTREMADAMENTE CONCISO (máximo ~3000 caracteres).
      3. ENFOCATE SOLO en la información más importante.

      INSTRUCCIONES IMPORTANTES:
      - Usa puntos para listas y sé breve en cada punto
      - Evita detalles excesivos y explicaciones largas
      - Resume detalles de implementación en vez de explicarlos por completo
      - Devuelve SOLO la descripción final, sin comentarios ni texto adicional
      - Evita cualquier texto redundante o innecesario

      INSTRUCCIONES PARA DIAGRAMAS MERMAID:
      - Incluye UN SOLO diagrama mermaid SOLO SI es absolutamente necesario
      - Usa sintaxis simple y válida para evitar errores de parsing
      - Evita caracteres especiales en los textos de los nodos
      - Usa nombres cortos para los nodos (A, B, C...)
      - Siempre escapa los corchetes dentro del texto con \[ y \]
      - NO uses comillas dentro del texto de los nodos
      - Asegura que cada nodo tiene un cierre correcto
      - Si incluyes un nodo con caracteres especiales, usa comillas para todo el texto

      Descripción actual:
      %s

      Cambios recientes:
      %s
      ]], old_desc, diff)
    else
      prompt = string.format([[
      You're an expert assistant in Pull Request documentation.

      MAIN INSTRUCTIONS:
      1. IMPROVE the description based on recent changes.
      2. BE EXTREMELY CONCISE (maximum ~3000 characters).
      3. FOCUS ONLY on the most important information.

      IMPORTANT GUIDELINES:
      - Use bullet points for lists and be brief with each point
      - Avoid excessive details and lengthy explanations
      - Summarize implementation details rather than explaining them fully
      - Return ONLY the final description, no comments or additional text
      - Avoid any redundant or unnecessary text

      MERMAID DIAGRAM GUIDELINES:
      - Include ONLY ONE small mermaid diagram IF absolutely necessary
      - Use simple and valid syntax to avoid parsing errors
      - Avoid special characters in node text
      - Use short node names (A, B, C...)
      - Always escape brackets in text with \[ and \]
      - DO NOT use quotes inside node text
      - Ensure each node has proper closure
      - If node includes special characters, use quotes for the entire text

      Current description:
      %s

      Recent changes:
      %s
      ]], old_desc, diff)
    end
  end

  -- Modificar el prompt para reducir complejidad y hacer más directa la solicitud
  local simplified_prompt

  if detected_language ~= target_language then
    simplified_prompt = string.format([[
    Translate and enhance this Pull Request description from %s to %s.
    The PR description should be well-formatted, clear, and contain all relevant information.
    Include or improve mermaid diagrams where appropriate.
    Return ONLY the final description, no comments or extra text.

    Current PR description (%s):
    %s

    Recent changes:
    %s
    ]], detected_language, target_language, detected_language, old_desc, diff)
  else
    simplified_prompt = string.format([[
    Enhance this Pull Request description (keeping it in %s).
    The PR description should be well-formatted, clear, and contain all relevant information.
    Include or improve mermaid diagrams where appropriate.
    Return ONLY the final description, no comments or extra text.

    Current PR description:
    %s

    Recent changes:
    %s
    ]], target_language, old_desc, diff)
  end

  -- Enviar solicitud asíncrona a CopilotChat con prompt más sencillo
  copilot_api.ask(simplified_prompt, {
    system_prompt = "You are an expert in documentation and translation focused on Pull Request descriptions. You provide clear, concise, and accurate descriptions with diagrams when helpful. For Mermaid diagrams, you use extremely simple and valid syntax to avoid parsing errors. You never use parentheses or special characters in node text. You use short node names like A, B, C with simple text descriptions.",
    callback = function(response)
      -- Detener el spinner con resultado exitoso si hay respuesta
      local success = response ~= nil
      progress.stop_spinner(spinner_id, success)

      -- Cancelar timeout timer
      if timeout_timer then
        timeout_timer:stop()
        timeout_timer:close()
      end

      log.debug("Recibida respuesta para enhance_pr (tipo: " .. type(response) .. ")")

      -- Extraer el contenido de la respuesta según su tipo
      local new_desc
      if type(response) == "string" then
        new_desc = response
      elseif type(response) == "table" and response.content then
        log.debug("Respuesta es una tabla con campo content, extrayendo...")
        new_desc = response.content
      else
        log.error("Formato de respuesta no reconocido")
        if type(response) == "table" then
          log.debug("Contenido de la tabla: " .. vim.inspect(response))
        end
        log.error("Error: formato de respuesta no reconocido.")
        return
      end

      -- Verificar que la descripción no está vacía y es diferente
      if new_desc and new_desc ~= "" and new_desc ~= old_desc then
        log.debug("Nueva descripción recibida, longitud: " .. #new_desc)

        -- Guardar la descripción para depuración
        local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
        vim.fn.mkdir(debug_dir, "p")
        local debug_file = debug_dir .. "/new_pr_description.txt"
        local f = io.open(debug_file, "w")
        if f then
          f:write(new_desc)
          f:close()
          log.debug("Nueva descripción guardada en " .. debug_file)
        end

        -- Mostrar notificación de progreso
        local action_msg = detected_language ~= target_language
          and "Descripción traducida y mejorada. Actualizando PR..."
          or "Descripción mejorada. Actualizando PR..."

        -- Actualizar la notificación existente con un timeout
        -- para asegurar que desaparezca si hay algún problema posterior
        notify.info(action_msg, {
          title = "PR Enhancement",
          timeout = 10000,  -- 10 segundos de timeout por si acaso
          replace = notify_id
        })

        -- Almacenamos una referencia para usar como backup
        local update_notify_id = notify_id

        -- Actualizar la descripción inmediatamente
        if update_pr_description(new_desc) then
          local success_msg = detected_language ~= target_language
            and string.format("PR description translated from %s to %s and enhanced successfully!", detected_language, target_language)
            or "PR description enhanced successfully!"

          -- Asegurar que la notificación se cierra después de mostrar el éxito
          -- Utilizamos timeout corto para que desaparezca
          -- En lugar de mostrar notificación, usar un spinner exitoso final
        local final_spinner_id = "enhance_pr_completed"
        progress.start_spinner(final_spinner_id, "PR enhancement completed", {
          style = options.get().progress_indicator_style,
          position = "statusline"
        })

        -- Detener el spinner automáticamente después de 2 segundos
        vim.defer_fn(function()
          progress.stop_spinner(final_spinner_id, true)
        end, 2000)

          -- No need to clean up notifications anymore  -- 5.5 segundos, justo después de que la notificación de éxito desaparezca

          -- Actualizar el estado del idioma si se realizó una traducción
          if detected_language ~= target_language then
            M.state.pr_language = target_language
          end
        else
          -- Mostrar un spinner de error en lugar de notificación
        local error_spinner_id = "pr_update_error"
        progress.start_spinner(error_spinner_id, "Error updating PR description", {
          style = options.get().progress_indicator_style,
          position = "statusline"
        })

        -- Detener el spinner con estado de error
        vim.defer_fn(function()
          progress.stop_spinner(error_spinner_id, false)
        end, 2000)
        end
      else
        if not new_desc or new_desc == "" then
          log.warn("La nueva descripción está vacía")
          -- Convert to debug log
          log.debug("Received empty PR description from CopilotChat.")
          local empty_notify_id = nil
        else
          log.info("La nueva descripción es idéntica a la original")
          -- Convert to debug log
          log.debug("No significant improvements to make to PR description.")
          local no_change_notify_id = nil
        end

        -- No need to clean up since we're using debug logs instead of notifications
      end
    end
  })
end

-- Función principal para cambiar el idioma de la descripción del PR
function M.change_pr_language(target_language)
  -- Validar idioma solicitado
  if not M.supported_languages[target_language] then
    log.error("Idioma no soportado: " .. target_language)
    notify.error("Idioma no soportado: " .. target_language)
    return
  end

  -- Obtener la descripción actual
  local old_desc = get_pr_description()
  if not old_desc or old_desc == "" then
    log.warn("No se encontró descripción del PR para traducir")
    notify.warn("No se encontró descripción del PR para traducir")
    return
  end

  -- Detectar idioma actual
  local current_detected_language = i18n.detect_language(old_desc)
  log.info("Idioma detectado en la descripción actual: " .. current_detected_language)

  -- Verificar si ya está en el idioma destino
  if current_detected_language == target_language then
    log.info("La descripción ya está en el idioma solicitado: " .. target_language)
    notify.info("La descripción del PR ya está en " .. target_language)
    return
  end

  -- Notificar al usuario
  notify.info("Traduciendo descripción del PR de " .. current_detected_language .. " a " .. target_language .. "...")
  log.info("Traduciendo descripción del PR de " .. current_detected_language .. " a " .. target_language)

  -- Log the activity instead of using spinner
  log.debug("Traduciendo descripción del PR...")

  -- Traducir la descripción de forma asíncrona
  log.debug("Iniciando traducción asíncrona de texto largo...")

  -- Usar i18n.translate_text con callback para procesamiento asíncrono
  i18n.translate_text(old_desc, target_language, function(translated_desc)
    -- Clear any status message
    vim.cmd("echo ''") -- Limpiar el mensaje de estado

    -- Verificar resultado de la traducción
    if not translated_desc or translated_desc == "" then
      log.error("Error al traducir la descripción del PR - respuesta vacía")
      notify.error("Error al traducir la descripción del PR")
      return
    end

    if translated_desc == old_desc then
      log.warn("La traducción no cambió el contenido original")
      notify.warn("La traducción no produjo cambios en el contenido")
      return
    end

    -- Guardar las descripciones para depuración
    local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    vim.fn.mkdir(debug_dir, "p")

    local orig_file = debug_dir .. "/pr_desc_original.md"
    local f = io.open(orig_file, "w")
    if f then
      f:write(old_desc)
      f:close()
      log.debug("Descripción original guardada en " .. orig_file)
    end

    local trans_file = debug_dir .. "/pr_desc_translated.md"
    local f = io.open(trans_file, "w")
    if f then
      f:write(translated_desc)
      f:close()
      log.debug("Descripción traducida guardada en " .. trans_file)
    end

    -- Esta verificación ya se realizó anteriormente, la omitimos

    -- Mostrar un resumen de la diferencia entre la original y la traducida
    log.debug("Descripción original - longitud: " .. #old_desc .. " caracteres")
    log.debug("Descripción traducida - longitud: " .. #translated_desc .. " caracteres")
    log.debug("Diferencia de longitud: " .. (#translated_desc - #old_desc) .. " caracteres")

    -- Actualizar la descripción del PR
    log.info("Actualizando descripción del PR en GitHub...")
    notify.info("Actualizando PR con descripción traducida...")

    -- Función para intentar actualizar con reintentos
    local function try_update(attempt)
      local max_attempts = 2

      if attempt > max_attempts then
        log.error("Error al actualizar la descripción del PR después de " .. max_attempts .. " intentos")
        notify.error("Error al actualizar la descripción del PR en GitHub")
        return
      end

      log.debug("Intento " .. attempt .. " de " .. max_attempts .. " para actualizar PR")

      -- Just log the action instead of showing spinner
      log.debug("Actualizando PR en GitHub...")

      -- Intentar la actualización
      local success = update_pr_description(translated_desc)

      -- Clear status line
      vim.cmd("echo ''")  -- Limpiar el mensaje

      -- Procesar el resultado
      if success then
        log.info("Descripción del PR traducida con éxito a " .. target_language)
        notify.success("Descripción del PR traducida con éxito a " .. target_language, {force = true})
        -- Actualizar el idioma registrado
        M.state.pr_language = target_language
      else
        if attempt < max_attempts then
          log.warn("Intento " .. attempt .. " falló. Reintentando en 2 segundos...")
          notify.warn("Error al actualizar PR. Reintentando...")
          -- Programar el próximo intento de forma asíncrona
          vim.defer_fn(function()
            try_update(attempt + 1)
          end, 2000)  -- Esperar 2 segundos
        else
          log.error("Error al actualizar la descripción traducida en GitHub")
          notify.error("Error al actualizar la descripción del PR en GitHub")
        end
      end
    end

    -- Iniciar el primer intento
    try_update(1)
  end)
end

-- Función simplificada que usa directamente CopilotChat para cambiar el idioma de un PR
-- @param target_language string: Idioma de destino para la descripción del PR
function M.simple_change_pr_language(target_language)
  -- Validar idioma solicitado
  if not M.supported_languages[target_language] then
    log.error("Idioma no soportado: " .. target_language)
    notify.error("Idioma no soportado: " .. target_language)
    return
  end

  -- Obtener la descripción actual del PR
  local old_desc = get_pr_description()
  if not old_desc or old_desc == "" then
    log.warn("No se encontró descripción del PR para traducir")
    notify.warn("No se encontró descripción del PR para traducir")
    return
  end

  -- Detectar idioma actual
  local current_detected_language = i18n.detect_language(old_desc)

  -- Verificar si ya está en el idioma destino
  if current_detected_language == target_language then
    log.info("La descripción ya está en el idioma solicitado: " .. target_language)
    notify.info("La descripción del PR ya está en " .. target_language)
    return
  end

  -- Utilizar el sistema de progreso visual centralizado
  local progress = require("copilotchatassist.utils.progress")
  local spinner_id = "change_pr_language"

  -- Iniciar spinner con mensaje en el idioma apropiado
  local message = "Translating PR from " .. current_detected_language .. " to " .. target_language
  if target_language == "spanish" then
    message = "Traduciendo PR de " .. current_detected_language .. " a " .. target_language
  end

  -- Iniciar spinner
  progress.start_spinner(spinner_id, message, {
    style = options.get().progress_indicator_style,
    position = "statusline"
  })

  -- Crear un prompt que le pida a CopilotChat traducir y actualizar en un solo paso
  local prompt = string.format([[
  Eres un asistente experto en traducción y documentación. Por favor traduce la siguiente
  descripción de Pull Request del idioma %s a %s, manteniendo el formato y estructura.

  IMPORTANTE: Debes devolver SÓLO el texto traducido listo para ser utilizado,
  sin ningún comentario adicional, explicación o formato markdown extra.

  SIEMPRE traduce los diagramas mermaid conservando su estructura y parámetros de estilo.
  SIEMPRE mantén intactos los nombres de código, variables y términos técnicos.
  SIEMPRE preserva el formato y la estructura del texto original.

  Descripción a traducir:

  %s
  ]], current_detected_language, target_language, old_desc)

  -- Enviar solicitud a CopilotChat
  copilot_api.ask(prompt, {
    system_prompt = "You are a translation expert focusing on technical documentation with precise formatting preservation.",
    callback = function(response)
      -- Detener el spinner del sistema de progreso
      local success = response ~= nil
      progress.stop_spinner(spinner_id, success)

      -- Procesar la respuesta
      local new_desc
      if type(response) == "string" then
        new_desc = response
      elseif type(response) == "table" and response.content then
        new_desc = response.content
      else
        log.error("Formato de respuesta no reconocido")
        notify.error("Error: formato de respuesta no reconocido", {
                    title = "PR Translation",
                    timeout = 5000,
                    replace = notify_id
                  })
        return
      end

      -- Verificar que obtuvimos una respuesta válida
      if not new_desc or new_desc == "" then
        log.error("La traducción devolvió un resultado vacío")
        notify.error("Error: traducción vacía", {
                    title = "PR Translation",
                    timeout = 5000,
                    replace = notify_id
                  })
        return
      end

      -- Guardar para debug
      local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
      vim.fn.mkdir(debug_dir, "p")
      local debug_file = debug_dir .. "/simple_pr_translation.md"
      local f = io.open(debug_file, "w")
      if f then
        f:write(new_desc)
        f:close()
        log.debug("Traducción guardada en " .. debug_file)
      end

      -- Actualizar el spinner en lugar de mostrar notificación
      progress.update_spinner(spinner_id, "Traducción completada. Actualizando PR...")

      -- Actualizar la descripción del PR
      local success = update_pr_description(new_desc)

      if success then
        log.info("PR actualizado correctamente a " .. target_language)

        -- En lugar de notificación, mostrar un spinner final con éxito
        local final_spinner_id = "translation_completed"
        progress.start_spinner(final_spinner_id, "PR translation completed", {
          style = options.get().progress_indicator_style,
          position = "statusline"
        })

        -- Detener el spinner automáticamente después de 2 segundos
        vim.defer_fn(function()
          progress.stop_spinner(final_spinner_id, true)
        end, 2000)

        -- Actualizar el idioma registrado
        M.state.pr_language = target_language
      else
        log.error("Error al actualizar la descripción del PR")

        -- Mostrar un spinner de error en lugar de notificación
        local error_spinner_id = "translation_error"
        progress.start_spinner(error_spinner_id, "Error updating PR description", {
          style = options.get().progress_indicator_style,
          position = "statusline"
        })

        -- Detener el spinner con estado de error
        vim.defer_fn(function()
          progress.stop_spinner(error_spinner_id, false)
        end, 2000)
      end
    end
  })
end

-- Registrar comando adicional para la versión simplificada
function M.register_simple_command()
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
end

return M