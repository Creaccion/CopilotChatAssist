-- Módulo de Code Review para CopilotChatAssist
-- Permite revisar código en Git diff utilizando CopilotChat y mantener un seguimiento de comentarios

local M = {}
local log = require("copilotchatassist.utils.log")
local options = require("copilotchatassist.options")
local i18n = require("copilotchatassist.i18n")
local copilot_api = require("copilotchatassist.copilotchat_api")
local file_utils = require("copilotchatassist.utils.file")

-- Submódulos que cargaremos bajo demanda
local analyzer, storage, window

-- Estado del módulo
M.state = {
  current_review = nil,        -- Revisión actual
  review_comments = {},        -- Lista de comentarios de la revisión
  selected_comment = nil,      -- Comentario seleccionado
  window_state = nil,          -- Estado de la ventana de visualización
  last_diff = nil,             -- Último diff analizado
  is_processing = false        -- Indica si hay un proceso de análisis en curso
}

-- Clasificaciones disponibles para los comentarios
M.classifications = {
  "Estético",       -- Relacionado con estilo de código y convenciones
  "Claridad",       -- Relacionado con legibilidad y comprensión
  "Funcionalidad",  -- Relacionado con comportamiento y lógica
  "Bug",            -- Errores y comportamientos incorrectos
  "Performance",    -- Problemas de rendimiento
  "Seguridad",      -- Problemas de seguridad
  "Mantenibilidad"  -- Relacionado con facilidad de mantenimiento a futuro
}

-- Estados disponibles para los comentarios
M.status_types = {
  "Abierto",      -- Comentario nuevo, no procesado
  "Modificado",   -- Se han hecho cambios pero no resuelve completamente
  "Retornado",    -- Se rechazó la sugerencia
  "Solucionado"   -- El problema ha sido resuelto
}

-- Severidades disponibles
M.severity_levels = {
  "Baja",    -- Sugerencia menor o cosmética
  "Media",   -- Mejora recomendada pero no crítica
  "Alta",    -- Problema importante que debe ser atendido
  "Crítica"  -- Problema que debe ser solucionado inmediatamente
}

-- Cargar submódulos bajo demanda
local function load_modules()
  if not analyzer then
    analyzer = require("copilotchatassist.code_review.analyzer")
  end

  if not storage then
    storage = require("copilotchatassist.code_review.storage")
  end

  if not window then
    window = require("copilotchatassist.code_review.window")
  end

  return analyzer, storage, window
end

-- Generar un identificador único para un comentario
local function generate_comment_id()
  return tostring(os.time()) .. "_" .. tostring(math.random(10000, 99999))
end

-- Crear un nuevo comentario de revisión
function M.create_comment(data)
  -- Traducir el comentario si es necesario
  local comment_text = data.comment or ""
  local current_language = i18n.get_current_language()

  -- Verificar si el comentario parece estar en un idioma diferente al configurado
  local seems_english = comment_text:match("%s+[Tt]he%s+") or
                      comment_text:match("%s+[Ii]s%s+") or
                      comment_text:match("%s+[Aa]re%s+") or
                      comment_text:match("^[Tt]he%s+")

  local seems_spanish = comment_text:match("%s+[Ee]l%s+") or
                       comment_text:match("%s+[Ll]a%s+") or
                       comment_text:match("%s+[Ee]stá%s+") or
                       comment_text:match("%s+[Ee]s%s+") or
                       comment_text:match("^[Ee]l%s+") or
                       comment_text:match("^[Ll]a%s+")

  local needs_translation = false

  -- Si el idioma es español y el comentario parece en inglés
  if current_language == "spanish" and seems_english and not seems_spanish then
    needs_translation = true
  -- Si el idioma es inglés y el comentario parece en español
  elseif current_language == "english" and seems_spanish and not seems_english then
    needs_translation = true
  end

  -- Crear el comentario con la traducción si es necesario
  local comment = {
    id = generate_comment_id(),
    file = data.file or "",
    line = data.line or 0,
    code_context = data.code_snippet or "",
    comment = comment_text,
    original_comment = needs_translation and comment_text or nil,  -- Guardar el original si hay traducción
    classification = data.classification or "Claridad",
    severity = data.severity or "Media",
    status = data.status or "Abierto",
    created_at = os.time(),
    updated_at = os.time(),
    hash = data.hash or "",
    needs_translation = needs_translation
  }

  table.insert(M.state.review_comments, comment)

  -- Si necesita traducción, intentar traducirlo y actualizar el comentario
  if needs_translation then
    -- Intentar traducir de forma asíncrona
    log.debug("Intentando traducir comentario a " .. current_language)

    -- Usar la función de traducción del módulo i18n
    i18n.translate_text(comment_text, current_language, function(translated_text)
      if translated_text and translated_text ~= comment_text then
        -- Actualizar el comentario con la traducción
        for i, c in ipairs(M.state.review_comments) do
          if c.id == comment.id then
            M.state.review_comments[i].comment = translated_text
            M.state.review_comments[i].is_translated = true
            break
          end
        end

        -- Actualizar la ventana si está abierta
        local _, _, window_module = load_modules()
        if window_module then
          window_module.refresh_window(M.state.review_comments)
        end
      end
    end)
  end

  return comment
end

-- Generar prompt para code review
local function generate_code_review_prompt(diff_content)
  local lang = options.get().language or "english"
  local prompt

  if lang == "spanish" then
    prompt = [[
Eres un revisor de código experto que genera comentarios de alta calidad siguiendo las mejores prácticas.
Analiza el siguiente código Git diff y genera comentarios detallados y constructivos.

Para cada comentario, DEBES usar EXACTAMENTE este formato JSON:
```json
{
  "file": "ruta/al/archivo.ext",
  "line": 123,
  "code_snippet": "fragmento relevante del código",
  "comment": "Descripción detallada del problema o mejora",
  "classification": "CLASIFICACIÓN",
  "severity": "SEVERIDAD"
}
```

Donde:
- CLASIFICACIÓN debe ser una de: "Estético", "Claridad", "Funcionalidad", "Bug", "Performance", "Seguridad", "Mantenibilidad"
- SEVERIDAD debe ser una de: "Baja", "Media", "Alta", "Crítica"

IMPORTANTE:
1. Genera SOLAMENTE comentarios en formato JSON válido, cada uno separado por una línea en blanco.
2. No incluyas ningún texto fuera del formato JSON especificado.
3. Enfócate en los problemas más importantes y en oportunidades de mejora significativas.
4. Incluye tanto aspectos positivos como negativos cuando sea relevante.
5. Proporciona sugerencias concretas y accionables para mejorar el código.
6. Considera el contexto del proyecto y las convenciones existentes.

Git Diff:
]]
  else
    prompt = [[
You're an expert code reviewer who generates high-quality comments following best practices.
Analyze the following Git diff and generate detailed, constructive comments.

For each comment, you MUST use EXACTLY this JSON format:
```json
{
  "file": "path/to/file.ext",
  "line": 123,
  "code_snippet": "relevant code snippet",
  "comment": "Detailed description of the issue or improvement",
  "classification": "CLASSIFICATION",
  "severity": "SEVERITY"
}
```

Where:
- CLASSIFICATION must be one of: "Aesthetic", "Clarity", "Functionality", "Bug", "Performance", "Security", "Maintainability"
- SEVERITY must be one of: "Low", "Medium", "High", "Critical"

IMPORTANT:
1. Generate ONLY valid JSON format comments, each separated by a blank line.
2. Do not include any text outside the specified JSON format.
3. Focus on the most important issues and significant improvement opportunities.
4. Include both positive and negative aspects when relevant.
5. Provide concrete and actionable suggestions to improve the code.
6. Consider the project context and existing conventions.

Git Diff:
]]
  end

  return prompt .. diff_content
end

-- Obtener diff del repositorio git actual de forma asíncrona
local function get_current_diff(callback)
  -- Callback debe ser una función
  callback = callback or function(diff) return diff end

  -- Obtener rama actual de forma asíncrona
  local function get_current_branch(on_branch_result)
    log.debug("Obteniendo rama actual de forma asíncrona...")
    local cmd_branch = "git branch --show-current"

    vim.fn.jobstart(cmd_branch, {
      on_stdout = function(_, data, _)
        local current_branch = table.concat(data, ""):gsub("%s+$", "")
        if not current_branch or current_branch == "" then
          current_branch = "HEAD"
        end
        log.debug("Rama actual: " .. current_branch)
        on_branch_result(current_branch)
      end,
      on_stderr = function(_, _, _)
        log.debug("Error al obtener rama actual, usando HEAD")
        on_branch_result("HEAD")
      end,
      stdout_buffered = true
    })
  end

  -- Obtener rama base de forma asíncrona
  local function get_base_branch(on_base_branch_result)
    log.debug("Obteniendo rama base de forma asíncrona...")
    local cmd_remote = "git remote show origin | grep 'HEAD branch' | awk '{print $3}'"

    vim.fn.jobstart(cmd_remote, {
      on_stdout = function(_, data, _)
        local remote_branch = table.concat(data, ""):gsub("%s+$", "")
        if remote_branch and remote_branch ~= "" then
          log.debug("Rama base detectada: " .. remote_branch)
          on_base_branch_result(remote_branch)
        else
          log.debug("No se detectó rama base, usando 'main'")
          on_base_branch_result("main")
        end
      end,
      on_stderr = function(_, _, _)
        log.debug("Error al obtener rama base, usando 'main'")
        on_base_branch_result("main")
      end,
      stdout_buffered = true
    })
  end

  -- Obtener diff entre ramas de forma asíncrona
  local function get_branch_diff(base_branch, on_branch_diff_result)
    local cmd_branch_diff = string.format("git diff --diff-algorithm=minimal origin/%s...HEAD", base_branch)
    log.debug("Ejecutando: " .. cmd_branch_diff)

    vim.fn.jobstart(cmd_branch_diff, {
      on_stdout = function(_, data, _)
        local branch_diff = table.concat(data, "\n")
        if branch_diff and branch_diff ~= "" then
          log.debug("Usando diff entre ramas (tamaño: " .. #branch_diff .. " bytes)")
          on_branch_diff_result(branch_diff)
        else
          log.debug("No se encontraron diferencias entre ramas, verificando cambios staged...")
          on_branch_diff_result(nil)
        end
      end,
      on_stderr = function(_, _, _)
        log.debug("Error al obtener diff entre ramas, verificando cambios staged...")
        on_branch_diff_result(nil)
      end,
      stdout_buffered = true
    })
  end

  -- Obtener cambios staged de forma asíncrona
  local function get_staged_diff(on_staged_diff_result)
    local cmd = "git diff --cached --diff-algorithm=minimal"
    log.debug("Ejecutando: " .. cmd)

    vim.fn.jobstart(cmd, {
      on_stdout = function(_, data, _)
        local staged_diff = table.concat(data, "\n")
        if staged_diff and staged_diff ~= "" then
          log.debug("Se encontraron cambios staged (tamaño: " .. #staged_diff .. " bytes)")
          on_staged_diff_result(staged_diff)
        else
          log.debug("No hay cambios staged, verificando cambios sin staging...")
          on_staged_diff_result(nil)
        end
      end,
      on_stderr = function(_, _, _)
        log.debug("Error al obtener cambios staged, verificando cambios sin staging...")
        on_staged_diff_result(nil)
      end,
      stdout_buffered = true
    })
  end

  -- Obtener cambios sin staging de forma asíncrona
  local function get_unstaged_diff(on_unstaged_diff_result)
    local cmd = "git diff --diff-algorithm=minimal"
    log.debug("Ejecutando: " .. cmd)

    vim.fn.jobstart(cmd, {
      on_stdout = function(_, data, _)
        local diff = table.concat(data, "\n")
        if diff and diff ~= "" then
          log.debug("Se encontraron cambios sin staging (tamaño: " .. #diff .. " bytes)")
          on_unstaged_diff_result(diff)
        else
          log.debug("No se encontraron cambios en el repositorio")
          on_unstaged_diff_result("")
        end
      end,
      on_stderr = function(_, _, _)
        log.debug("Error al obtener cambios sin staging")
        on_unstaged_diff_result("")
      end,
      stdout_buffered = true
    })
  end

  -- Comenzar la cadena de operaciones asíncronas
  get_current_branch(function(_)
    get_base_branch(function(base_branch)
      get_branch_diff(base_branch, function(branch_diff)
        if branch_diff then
          -- Si hay diff entre ramas, usarlo directamente
          callback(branch_diff)
        else
          -- Si no hay diff entre ramas, verificar cambios staged
          get_staged_diff(function(staged_diff)
            if staged_diff then
              -- Si hay cambios staged, usarlos
              callback(staged_diff)
            else
              -- Si no hay cambios staged, verificar cambios sin staging
              get_unstaged_diff(function(unstaged_diff)
                callback(unstaged_diff or "")
              end)
            end
          end)
        end
      end)
    end)
  end)
end

-- Parsear comentarios de la respuesta de CopilotChat
local function parse_comments(response)
  if not response or response == "" then
    log.debug("No se pudo parsear comentarios: respuesta vacía o nil")
    return {}
  end

  -- Si la respuesta es una tabla, extraer el contenido
  if type(response) == "table" then
    if response.content then
      response = response.content
      log.debug("Extrayendo contenido de respuesta tipo tabla")
    else
      log.debug("Respuesta en formato tabla pero sin propiedad 'content'")
      return {}
    end
  end

  -- Guardar respuesta para debug avanzado
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")
  local raw_debug_file = io.open(debug_dir .. "/json_parse_debug.txt", "w")
  if raw_debug_file then
    raw_debug_file:write("Tipo: " .. type(response) .. "\n\n")
    raw_debug_file:write(tostring(response) .. "\n")
    raw_debug_file:close()
    log.debug("Respuesta guardada para debug avanzado de parseo")
  end

  local comments = {}
  local json_pattern = '(%b{})'

  -- Sanitizar respuesta: manejar caracteres problemáticos
  local sanitized_response = response

  -- Eliminar posibles backticks markdown que envuelven JSON
  sanitized_response = sanitized_response:gsub('```json\r?\n?', '')
  sanitized_response = sanitized_response:gsub('```\r?\n?', '')

  -- Escapar barras invertidas no seguidas de comillas
  sanitized_response = sanitized_response:gsub('\\([^"\\])', '\\\\%1')

  log.debug("Buscando patrones JSON en respuesta...")
  local json_count = 0

  for json_str in sanitized_response:gmatch(json_pattern) do
    json_count = json_count + 1
    log.debug("Encontrado potencial JSON #" .. json_count)

    -- Limpieza adicional para JSON malformado
    local cleaned_json = json_str

    -- Verificar y corregir errores comunes de formato JSON
    cleaned_json = cleaned_json:gsub('\\r', '')
    cleaned_json = cleaned_json:gsub('\\t', '  ')

    -- Intentar parsear el JSON
    local success, comment = pcall(function()
      return vim.json.decode(cleaned_json)
    end)

    -- Si falla, intentar un último arreglo
    if not success and type(comment) == "string" then
      log.debug("Error decodificando JSON: " .. comment)
      log.debug("Intentando limpieza alternativa...")

      -- Guardar el JSON problemático para análisis
      local debug_file = io.open(debug_dir .. "/failed_json_" .. json_count .. ".txt", "w")
      if debug_file then
        debug_file:write(cleaned_json)
        debug_file:close()
      end

      -- Intentar arreglos adicionales para JSON malformado
      cleaned_json = cleaned_json:gsub('\\"', '\\\\"')  -- Escapar mejor las comillas

      success, comment = pcall(vim.json.decode, cleaned_json)
    end

    if success and type(comment) == "table" then
      -- Verificar que el comentario tiene los campos mínimos necesarios
      if comment.file and comment.comment then
        table.insert(comments, comment)
        log.debug("JSON #" .. json_count .. " parseado con éxito")
      else
        log.debug("JSON parseado pero faltan campos requeridos (file o comment)")
      end
    else
      log.debug("No se pudo parsear JSON #" .. json_count .. ": " .. tostring(comment))
    end
  end

  log.debug("Total de comentarios extraídos correctamente: " .. #comments)
  return comments
end

-- Diagnóstico detallado para ayudar a depurar problemas con code_review
local function show_diagnostic_info()
  -- Solo mostrar en nivel DEBUG
  if options.get().log_level < vim.log.levels.DEBUG then
    return
  end

  log.debug("--- DIAGNÓSTICO DE CODE REVIEW ---")

  -- Verificar si CopilotChat está disponible
  local ok, CopilotChat = pcall(require, "CopilotChat")
  if not ok then
    log.debug("Estado de CopilotChat: NO DISPONIBLE")
    vim.notify("[CopilotChatAssist] CopilotChat no está disponible. Verifica la instalación.", vim.log.levels.WARN)
  else
    log.debug("Estado de CopilotChat: DISPONIBLE")
    if type(CopilotChat.ask) == "function" then
      log.debug("CopilotChat.ask: DISPONIBLE (tipo función)")
    else
      log.debug("CopilotChat.ask: NO DISPONIBLE (tipo: " .. type(CopilotChat.ask) .. ")")
    end
  end

  -- Verificar estado global
  log.debug("copilotchatassist_debug: " .. tostring(vim.g.copilotchatassist_debug))
  log.debug("copilotchatassist_force_debug: " .. tostring(vim.g.copilotchatassist_force_debug))
  log.debug("log_level configurado: " .. tostring(options.get().log_level))

  -- Verificar si Git está disponible
  local git_version = vim.fn.system("git --version")
  if vim.v.shell_error == 0 then
    log.debug("Git disponible: " .. string.gsub(git_version, "\n", ""))
  else
    log.debug("Git NO disponible")
  end

  -- Verificar si estamos en un repositorio Git
  local git_dir = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null")
  if vim.v.shell_error == 0 then
    log.debug("Directorio Git válido: SÍ")
  else
    log.debug("Directorio Git válido: NO")
    vim.notify("[CopilotChatAssist] No estás en un repositorio Git válido. Esto podría afectar Code Review.", vim.log.levels.WARN)
  end

  log.debug("--------------------------------")
end

-- Iniciar una nueva revisión de código
function M.start_review()
  log.info(i18n.t("code_review.starting_review"))

  -- Mostrar información de diagnóstico
  show_diagnostic_info()

  -- Marcar como procesando
  M.state.is_processing = true

  -- Iniciar spinner de progreso
  local progress = require("copilotchatassist.utils.progress")
  local spinner_id = "code_review"
  progress.start_spinner(spinner_id, i18n.t("code_review.starting_review"), {
    style = options.get().progress_indicator_style,
    position = "statusline"
  })

  -- Configurar un timeout para evitar procesamiento infinito
  local timeout_timer = vim.loop.new_timer()
  timeout_timer:start(120000, 0, vim.schedule_wrap(function()
    -- Si después de 2 minutos aún está procesando, cancelar
    if M.state.is_processing then
      log.error("Timeout alcanzado en code review. La operación tomó demasiado tiempo.")
      vim.notify("Timeout en code review. La operación tomó demasiado tiempo.", vim.log.levels.ERROR)

      -- Detener el spinner con error
      progress.stop_spinner(spinner_id, false)

      -- Marcar como no procesando
      M.state.is_processing = false
    end

    -- Limpiar el timer
    timeout_timer:stop()
    timeout_timer:close()
  end))

  -- Obtener diff actual de forma asíncrona
  log.debug("Obteniendo diff actual de forma asíncrona...")
  get_current_diff(function(diff)
    if not diff or diff == "" then
      log.warn(i18n.t("code_review.no_changes"))
      -- Detener spinner con error
      progress.stop_spinner("code_review", false)
      M.state.is_processing = false
      return
    end

    log.debug("Diff obtenido con éxito. Tamaño: " .. #diff .. " bytes")

    -- Guardar diff para depuración de forma asíncrona
    vim.schedule(function()
      local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
      vim.fn.mkdir(debug_dir, "p")
      local diff_file = debug_dir .. "/code_review_diff.txt"
      local diff_debug_file = io.open(diff_file, "w")
      if diff_debug_file then
        diff_debug_file:write(diff)
        diff_debug_file:close()
        log.debug("Diff guardado para depuración en: " .. diff_file)
      end
    end)

    M.state.last_diff = diff

    -- Guardar info de revisión actual
    M.state.current_review = {
      id = tostring(os.time()),
      started_at = os.time(),
      updated_at = os.time()
    }

    -- Generar prompt y enviar a CopilotChat
    log.debug("Generando prompt para code review...")
    local prompt = generate_code_review_prompt(diff)
    log.debug("Longitud del prompt generado: " .. #prompt .. " bytes")

    -- Guardar prompt para depuración de forma asíncrona
    vim.schedule(function()
      local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
      vim.fn.mkdir(debug_dir, "p")
      local prompt_file = debug_dir .. "/code_review_prompt.txt"
      local prompt_debug_file = io.open(prompt_file, "w")
      if prompt_debug_file then
        prompt_debug_file:write(prompt)
        prompt_debug_file:close()
        log.debug("Prompt guardado para depuración en: " .. prompt_file)
      end
    end)

    -- Usar copilot_api para enviar el prompt
    local current_language = i18n.get_current_language()
    log.debug("Idioma detectado para code review: " .. current_language)
    local system_prompt

    if current_language == "spanish" then
      system_prompt = "Eres un revisor de código experto que genera comentarios estructurados y accionables en el formato JSON exacto solicitado. Tus comentarios deben estar completamente en español, incluyendo todo el contenido dentro del JSON."
    else
      system_prompt = "You are an expert code reviewer who generates structured, actionable feedback in the exact JSON format requested. Your comments must be completely in English, including all content within the JSON."
    end

    -- Notificar inicio de envío
    vim.notify("[CopilotChatAssist] Enviando solicitud a CopilotChat. Esto puede tomar un momento...", vim.log.levels.INFO)

    log.debug("Enviando solicitud a CopilotChat...")
    log.debug("Devolviendo todo el texto como código")
    copilot_api.ask(prompt, {
      system_prompt = system_prompt,
      callback = function(response)
        log.debug("Respuesta recibida de CopilotChat. Tipo de respuesta: " .. type(response))
        -- Procesar respuesta
        local content = response
        if type(response) == "table" and response.content then
          content = response.content
        elseif type(response) ~= "string" then
          log.error(i18n.t("code_review.invalid_response"))
          -- Detener spinner con error
          progress.stop_spinner("code_review", false)
          M.state.is_processing = false
          return
        end

        -- Guardar respuesta raw para debug de forma asíncrona
        vim.schedule(function()
          local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
          vim.fn.mkdir(debug_dir, "p")
          local raw_file = debug_dir .. "/code_review_raw.txt"
          local raw_debug_file = io.open(raw_file, "w")
          if raw_debug_file then
            raw_debug_file:write(content or "")
            raw_debug_file:close()
            log.debug(i18n.t("code_review.saved_debug_file", {raw_file}))

            -- Notificar al usuario sobre el archivo de debug
            vim.notify("[CopilotChatAssist] Respuesta guardada en " .. raw_file, vim.log.levels.INFO)
          end
        end)

        -- Mostrar los primeros bytes de la respuesta para diagnosticar problemas
        if type(content) == "string" then
          local preview = content:sub(1, 100):gsub("\n", " ")
          log.debug("Vista previa de respuesta: " .. preview .. "...")

          -- Intentar determinar si la respuesta tiene forma de JSON
          local has_json = content:match("^%s*{") ~= nil or content:match("```json%s*{") ~= nil
          log.debug("Formato de respuesta probablemente JSON: " .. tostring(has_json))
        else
          log.debug("Respuesta no es string, no se puede mostrar vista previa")
        end

        -- Parsear comentarios de forma asíncrona
        vim.schedule(function()
          local comments = parse_comments(content)

          if #comments == 0 then
            log.warn(i18n.t("code_review.no_comments_found"))
            vim.notify("[CopilotChatAssist] No se encontraron comentarios en el Code Review. " ..
                      "Esto puede deberse a un error en el formato de la respuesta. " ..
                      "Verifica el archivo de log y ejecuta :messages para más detalles.", vim.log.levels.WARN)

            -- Crear un log especial con la respuesta formateada para facilitar el diagnóstico
            vim.schedule(function()
              local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
              local formatted_file = debug_dir .. "/code_review_formatted.txt"
              local f = io.open(formatted_file, "w")
              if f and type(content) == "string" then
                -- Intentar formatear el contenido para facilitar diagnóstico
                local formatted = content:gsub("```json", "\n---JSON BLOCK START---\n"):gsub("```", "\n---JSON BLOCK END---\n")
                f:write("RESPUESTA FORMATEADA PARA DIAGNÓSTICO:\n\n")
                f:write(formatted)
                f:close()
                log.debug("Respuesta formateada guardada en " .. formatted_file)
                vim.notify("[CopilotChatAssist] Respuesta formateada guardada en " .. formatted_file, vim.log.levels.INFO)
              end
            end)

            -- Detener spinner con estado neutro
            progress.stop_spinner("code_review", false) -- Cambio a false para indicar error
            M.state.is_processing = false
            return
          end

          log.info(i18n.t("code_review.found_comments", {#comments}))

          -- Añadir comentarios a la revisión
          M.state.review_comments = {}
          for _, comment_data in ipairs(comments) do
            M.create_comment(comment_data)
          end

          -- Cargar módulos necesarios - IMPORTANTE: Los cargamos solo una vez y guardamos las referencias
          -- Evitar cargar módulos múltiples veces puede prevenir callbacks adicionales
          local analyzer_module = M.analyzer_module
          local storage_module = M.storage_module
          local window_module = M.window_module

          -- Si no tenemos los módulos cargados aún, cargarlos ahora
          if not analyzer_module or not storage_module or not window_module then
            analyzer_module, storage_module, window_module = load_modules()
            -- Guardar referencias para evitar cargas múltiples
            M.analyzer_module = analyzer_module
            M.storage_module = storage_module
            M.window_module = window_module
          end

          -- Guardar revisión de forma asíncrona
          vim.schedule(function()
            if storage_module then
              storage_module.save_review(M.state.current_review, M.state.review_comments)
            end

            -- Mostrar resultados
            if window_module then
              window_module.show_review_window(M.state.review_comments)
            end

            -- Mostrar spinner de éxito
            progress.stop_spinner("code_review", true)

            -- Iniciar un spinner final que muestre el resultado
            local complete_spinner_id = "code_review_complete"
            progress.start_spinner(complete_spinner_id, i18n.t("code_review.review_completed", {#comments}), {
              style = options.get().progress_indicator_style,
              position = "statusline"
            })

            -- Detener el spinner de completado después de 2 segundos
            vim.defer_fn(function()
              progress.stop_spinner(complete_spinner_id, true)
            end, 2000)

            -- Marcar como completado
            M.state.is_processing = false
          end)
        end)
      end
    })
  end)
end

-- Mostrar comentarios de la revisión actual
function M.show_review_comments()
  local _, _, window_module = load_modules()

  if not M.state.review_comments or #M.state.review_comments == 0 then
    local _, storage_module = load_modules()

    -- Intentar cargar la última revisión
    if storage_module then
      local last_review, comments = storage_module.load_last_review()
      if last_review and comments and #comments > 0 then
        M.state.current_review = last_review
        M.state.review_comments = comments
      end
    end

    if not M.state.review_comments or #M.state.review_comments == 0 then
      log.warn(i18n.t("code_review.no_current_review"))
      vim.notify(i18n.t("code_review.no_current_review"), vim.log.levels.WARN)
      return
    end
  end

  -- Mostrar ventana de comentarios
  if window_module then
    window_module.show_review_window(M.state.review_comments)
  end
end

-- Mostrar estadísticas de la revisión actual
function M.show_review_stats()
  if not M.state.review_comments or #M.state.review_comments == 0 then
    local _, storage_module = load_modules()

    -- Intentar cargar la última revisión
    if storage_module then
      local last_review, comments = storage_module.load_last_review()
      if last_review and comments and #comments > 0 then
        M.state.current_review = last_review
        M.state.review_comments = comments
      else
        log.warn(i18n.t("code_review.no_current_review"))
        vim.notify(i18n.t("code_review.no_current_review"), vim.log.levels.WARN)
        return
      end
    else
      log.warn(i18n.t("code_review.no_current_review"))
      vim.notify(i18n.t("code_review.no_current_review"), vim.log.levels.WARN)
      return
    end
  end

  -- Calcular estadísticas
  local stats = {
    total = #M.state.review_comments,
    by_classification = {},
    by_severity = {},
    by_status = {},
    by_file = {}
  }

  -- Inicializar contadores
  for _, classification in ipairs(M.classifications) do
    stats.by_classification[classification] = 0
  end

  for _, severity in ipairs(M.severity_levels) do
    stats.by_severity[severity] = 0
  end

  for _, status in ipairs(M.status_types) do
    stats.by_status[status] = 0
  end

  -- Procesar comentarios
  for _, comment in ipairs(M.state.review_comments) do
    -- Por clasificación
    local classification = comment.classification
    stats.by_classification[classification] = (stats.by_classification[classification] or 0) + 1

    -- Por severidad
    local severity = comment.severity
    stats.by_severity[severity] = (stats.by_severity[severity] or 0) + 1

    -- Por estado
    local status = comment.status
    stats.by_status[status] = (stats.by_status[status] or 0) + 1

    -- Por archivo
    local file = comment.file
    stats.by_file[file] = (stats.by_file[file] or 0) + 1
  end

  -- Mostrar estadísticas
  local _, _, window_module = load_modules()
  if window_module then
    window_module.show_stats_window(stats)
  else
    -- Mostrar estadísticas básicas como notificación
    local msg = i18n.t("code_review.stats_summary", {
      stats.total,
      stats.by_status["Abierto"] or 0,
      stats.by_status["Solucionado"] or 0,
      stats.by_severity["Alta"] + (stats.by_severity["Crítica"] or 0)
    })

    vim.notify(msg, vim.log.levels.INFO)
  end
end

-- Exportar revisión a archivo JSON
function M.export_review(path)
  if not M.state.review_comments or #M.state.review_comments == 0 then
    local _, storage_module = load_modules()

    -- Intentar cargar la última revisión
    if storage_module then
      local last_review, comments = storage_module.load_last_review()
      if last_review and comments and #comments > 0 then
        M.state.current_review = last_review
        M.state.review_comments = comments
      else
        log.warn(i18n.t("code_review.no_current_review"))
        vim.notify(i18n.t("code_review.no_current_review"), vim.log.levels.WARN)
        return
      end
    else
      log.warn(i18n.t("code_review.no_current_review"))
      vim.notify(i18n.t("code_review.no_current_review"), vim.log.levels.WARN)
      return
    end
  end

  -- Si no se especificó ruta, usar directorio actual con timestamp
  if not path or path == "" then
    local timestamp = os.date("%Y%m%d_%H%M%S")
    path = "code_review_" .. timestamp .. ".json"
  end

  -- Crear objeto de exportación
  local export_data = {
    review = M.state.current_review,
    comments = M.state.review_comments
  }

  -- Convertir a JSON
  local json_str = vim.json.encode(export_data)

  -- Guardar a archivo
  local success = file_utils.write_file(path, json_str)

  if success then
    log.info(i18n.t("code_review.export_success", {path}))
    vim.notify(i18n.t("code_review.export_success", {path}), vim.log.levels.INFO)
  else
    log.error(i18n.t("code_review.export_failed", {path}))
    vim.notify(i18n.t("code_review.export_failed", {path}), vim.log.levels.ERROR)
  end
end

-- Actualizar el estado de un comentario
function M.update_comment_status(comment_id, new_status)
  for i, comment in ipairs(M.state.review_comments) do
    if comment.id == comment_id then
      M.state.review_comments[i].status = new_status
      M.state.review_comments[i].updated_at = os.time()

      -- Guardar cambios
      local _, storage_module = load_modules()
      if storage_module then
        storage_module.save_review(M.state.current_review, M.state.review_comments)
      end

      return true
    end
  end

  return false
end

-- Re-analizar un diff y actualizar comentarios de forma asíncrona
function M.reanalyze_diff()
  -- Iniciar spinner de progreso
  local progress = require("copilotchatassist.utils.progress")
  local spinner_id = "code_review_reanalyze"
  progress.start_spinner(spinner_id, i18n.t("code_review.reanalyzing_diff"), {
    style = options.get().progress_indicator_style,
    position = "statusline"
  })

  -- Obtener diff actual de forma asíncrona
  get_current_diff(function(diff)
    if not diff or diff == "" then
      log.warn(i18n.t("code_review.no_changes"))
      vim.notify(i18n.t("code_review.no_changes"), vim.log.levels.WARN)
      progress.stop_spinner(spinner_id, false)
      return
    end

    M.state.last_diff = diff

    -- Cargar el analizador de forma asíncrona
    vim.schedule(function()
      local analyzer_module = load_modules()

      if analyzer_module then
        -- Ejecutar el análisis en un contexto programado para evitar bloqueos
        vim.schedule(function()
          local updated_comments = analyzer_module.analyze_diff_changes(diff, M.state.review_comments)

          if updated_comments then
            M.state.review_comments = updated_comments

            -- Actualizar timestamp
            if M.state.current_review then
              M.state.current_review.updated_at = os.time()
            end

            -- Guardar cambios de forma asíncrona
            vim.schedule(function()
              local _, storage_module = load_modules()
              if storage_module then
                storage_module.save_review(M.state.current_review, M.state.review_comments)
              end

              -- Actualizar ventana si está abierta
              local _, _, window_module = load_modules()
              if window_module then
                window_module.refresh_window(M.state.review_comments)
              end

              -- Indicar éxito
              progress.stop_spinner(spinner_id, true)
              vim.notify(i18n.t("code_review.reanalysis_complete"), vim.log.levels.INFO)
            end)
          else
            progress.stop_spinner(spinner_id, false)
          end
        end)
      else
        progress.stop_spinner(spinner_id, false)
      end
    end)
  end)
end

-- Reiniciar/limpiar la revisión actual
function M.reset_review()
  -- Reiniciar el estado
  M.state.current_review = nil
  M.state.review_comments = {}
  M.state.last_diff = nil
  M.state.is_processing = false

  -- Cerrar la ventana de comentarios si está abierta
  local _, _, window_module = load_modules()
  if window_module then
    window_module.close_window()
  end

  -- Notificar al usuario
  vim.notify(i18n.t("code_review.review_reset"), vim.log.levels.INFO)

  return true
end

return M