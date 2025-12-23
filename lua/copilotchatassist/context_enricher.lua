-- Módulo para enriquecer el contexto con información relevante de archivos
-- Identifica y añade automáticamente archivos relevantes para un ticket o contexto

local M = {}

local log = require("copilotchatassist.utils.log")
local file_utils = require("copilotchatassist.utils.file")
local copilot_api = require("copilotchatassist.copilotchat_api")
local context = require("copilotchatassist.context")
local utils = require("copilotchatassist.utils")
local notify = require("copilotchatassist.utils.notify")
local progress = require("copilotchatassist.utils.progress")

-- Configuración por defecto
M.config = {
  max_files = 10,           -- Número máximo de archivos a incluir
  max_file_size = 50000,    -- Tamaño máximo por archivo (caracteres)
  min_relevance_score = 0.7, -- Puntuación mínima de relevancia (0-1)
  exclude_patterns = {      -- Patrones de archivos a excluir
    "%.git/",
    "node_modules/",
    "%.min%.js$",
    "dist/",
    "build/",
    "vendor/",
    "%.lock$"
  },
  file_content_preview = 500,  -- Caracteres a mostrar por archivo en preview
  include_patterns = {},    -- Patrones adicionales a incluir siempre
  max_analysis_time = 30,   -- Tiempo máximo de análisis en segundos
}

-- Estado del enriquecedor
M.state = {
  is_analyzing = false,
  current_ticket = nil,
  identified_files = {},
  context_files = {},
  last_analysis_time = nil,
}

-- Prompt para identificar archivos relevantes
local function generate_analysis_prompt(ticket_content, project_context)
  return [[
Eres un asistente de desarrollo especializado en identificar los archivos más relevantes para un contexto de desarrollo.

Tu tarea es analizar un ticket o requerimiento y determinar qué archivos del proyecto serían más relevantes para implementar o comprender esta tarea.

INSTRUCCIONES IMPORTANTES:
1. Analiza el ticket/requerimiento proporcionado.
2. Determina qué partes del código serían más relevantes para esta tarea.
3. Identifica patrones de archivos o directorios que probablemente contengan código relacionado.
4. Proporciona una lista de patrones de búsqueda (glob) que se deberían examinar.
5. También proporciona una lista de consultas de grep específicas que ayudarían a encontrar código relevante.

Responde ÚNICAMENTE con un objeto JSON con el siguiente formato:
{
  "file_patterns": ["path/to/relevant/**/*.js", "another/path/**/*.ts"],
  "grep_patterns": ["relevant_function_name", "ClassOfInterest", "keyTermFromTicket"],
  "explanation": "Breve explicación de por qué estos patrones son relevantes",
  "suggested_files": ["path/to/specific/file.js", "another/specific/file.ts"]
}

No incluyas texto adicional fuera del objeto JSON.

REQUERIMIENTO/TICKET:
]] .. (ticket_content or "") .. [[

CONTEXTO DEL PROYECTO (si está disponible):
]] .. (project_context or "")
end

-- Función para solicitar el análisis previo a Copilot
function M.analyze_ticket_for_relevant_files(ticket_content, callback)
  if M.state.is_analyzing then
    log.warn("Ya hay un análisis en progreso")
    if callback then callback(false, "Análisis ya en progreso") end
    return
  end

  M.state.is_analyzing = true

  -- Iniciar indicador de progreso
  local spinner_id = "analyze_ticket_files"
  progress.start_spinner(spinner_id, "Analizando ticket para identificar archivos relevantes", {
    style = "dots",
    position = "statusline"
  })

  -- Obtener contexto del proyecto si está disponible
  local paths = context.get_context_paths()
  local project_context = file_utils.read_file(paths.project_context) or ""

  -- Preparar prompt para análisis
  local prompt = generate_analysis_prompt(ticket_content, project_context)

  -- Solicitar análisis a Copilot
  copilot_api.ask(prompt, {
    headless = true,
    system_prompt = "Eres un asistente especializado en desarrollo de software que identifica archivos relevantes para un contexto específico. Respondes únicamente en formato JSON.",
    callback = function(response)
      progress.update_spinner(spinner_id, "Procesando resultados del análisis")

      -- Procesar respuesta
      if not response or response == "" then
        log.error("No se recibió respuesta del análisis")
        progress.stop_spinner(spinner_id, false)
        M.state.is_analyzing = false
        if callback then callback(false, "No se recibió respuesta del análisis") end
        return
      end

      -- Extraer JSON de la respuesta
      local json_str = response
      if type(response) == "table" then
        -- Buscar content en diferentes ubicaciones posibles
        if response.content then
          json_str = response.content
        elseif response[1] and type(response[1]) == "string" then
          json_str = response[1]
        elseif response.text then
          json_str = response.text
        elseif response.message then
          json_str = response.message
        end
      end

      log.debug("Tipo de respuesta recibida: " .. type(json_str))

      -- Intentar limpiar el JSON (eliminar backticks si hay)
      json_str = json_str:gsub("```json", ""):gsub("```", ""):gsub("^%s*(.-)%s*$", "%1")

      -- Intentar parsear el JSON
      local ok, analysis = pcall(vim.json.decode, json_str)
      if not ok or not analysis then
        log.error("Error al parsear respuesta JSON: " .. json_str:sub(1, 100) .. "...")
        progress.stop_spinner(spinner_id, false)
        M.state.is_analyzing = false
        if callback then callback(false, "Error al parsear respuesta") end
        return
      end

      -- Guardar resultados
      M.state.identified_files = analysis
      M.state.last_analysis_time = os.time()

      -- Finalizar progreso
      progress.stop_spinner(spinner_id, true)
      M.state.is_analyzing = false

      -- Logear resultados
      log.debug("Análisis completado. Patrones identificados: " ..
                vim.inspect(analysis.file_patterns) .. ", " ..
                "Consultas grep: " .. vim.inspect(analysis.grep_patterns))

      if callback then callback(true, analysis) end
    end,
    timeout = M.config.max_analysis_time * 1000
  })
end

-- Función para buscar archivos según los patrones identificados
function M.search_relevant_files(analysis, callback)
  if not analysis or not analysis.file_patterns then
    if callback then callback(false, "Análisis inválido") end
    return {}
  end

  -- Iniciar indicador de progreso
  local spinner_id = "search_files"
  progress.start_spinner(spinner_id, "Buscando archivos relevantes", {
    style = "dots",
    position = "statusline"
  })

  local found_files = {}
  local pending_searches = #analysis.file_patterns

  -- Función para verificar si todos los patrones se han procesado
  local function check_completion()
    pending_searches = pending_searches - 1
    if pending_searches <= 0 then
      progress.stop_spinner(spinner_id, true)

      -- Deduplicar archivos
      local unique_files = {}
      for _, file in ipairs(found_files) do
        unique_files[file] = true
      end

      local result = {}
      for file, _ in pairs(unique_files) do
        table.insert(result, file)
      end

      -- Ordenar por relevancia (por ahora, simplemente alfabéticamente)
      table.sort(result)

      -- Limitar cantidad de archivos
      if #result > M.config.max_files then
        result = { unpack(result, 1, M.config.max_files) }
      end

      log.debug("Archivos encontrados: " .. #result)

      -- Guardar en estado
      M.state.context_files = result

      if callback then callback(true, result) end
      return result
    end
  end

  -- Buscar para cada patrón de archivo
  for _, pattern in ipairs(analysis.file_patterns) do
    -- Usar patrón relativo a la raíz del proyecto
    local root = vim.fn.getcwd()

    -- Ejecutar búsqueda de archivos
    vim.fn.jobstart("find " .. root .. " -type f -path \"" .. pattern .. "\" 2>/dev/null", {
      on_stdout = function(_, data)
        if data then
          for _, file in ipairs(data) do
            if file and file ~= "" then
              -- Verificar exclusiones
              local excluded = false
              for _, exclude in ipairs(M.config.exclude_patterns) do
                if file:match(exclude) then
                  excluded = true
                  break
                end
              end

              if not excluded then
                table.insert(found_files, file)
              end
            end
          end
        end
      end,
      on_exit = function()
        progress.update_spinner(spinner_id, "Buscando (" .. #found_files .. " archivos encontrados)")
        check_completion()
      end
    })
  end

  -- Si no hay patrones, completar inmediatamente
  if #analysis.file_patterns == 0 then
    progress.stop_spinner(spinner_id, true)
    if callback then callback(true, {}) end
    return {}
  end

  return found_files
end

-- Función para buscar código mediante grep según los patrones identificados
function M.search_with_grep(analysis, callback)
  if not analysis or not analysis.grep_patterns or #analysis.grep_patterns == 0 then
    if callback then callback(false, "No hay patrones para grep") end
    return {}
  end

  -- Iniciar indicador de progreso
  local spinner_id = "grep_code"
  progress.start_spinner(spinner_id, "Buscando código relevante", {
    style = "dots",
    position = "statusline"
  })

  local found_files = {}
  local pending_searches = #analysis.grep_patterns

  -- Función para verificar si todos los patrones se han procesado
  local function check_completion()
    pending_searches = pending_searches - 1
    if pending_searches <= 0 then
      progress.stop_spinner(spinner_id, true)

      -- Deduplicar archivos
      local unique_files = {}
      for _, file in ipairs(found_files) do
        unique_files[file] = true
      end

      local result = {}
      for file, _ in pairs(unique_files) do
        table.insert(result, file)
      end

      -- Ordenar por relevancia (por ahora, simplemente alfabéticamente)
      table.sort(result)

      -- Limitar cantidad de archivos
      if #result > M.config.max_files then
        result = { unpack(result, 1, M.config.max_files) }
      end

      log.debug("Archivos encontrados con grep: " .. #result)

      -- Añadir a los archivos de contexto
      for _, file in ipairs(result) do
        if not vim.tbl_contains(M.state.context_files, file) then
          table.insert(M.state.context_files, file)
        end
      end

      -- Limitar cantidad de archivos total
      if #M.state.context_files > M.config.max_files then
        M.state.context_files = { unpack(M.state.context_files, 1, M.config.max_files) }
      end

      if callback then callback(true, result) end
      return result
    end
  end

  -- Buscar para cada patrón de grep
  for _, pattern in ipairs(analysis.grep_patterns) do
    -- Escapar patrón para grep
    local escaped_pattern = pattern:gsub("([%^%$%.%[%]%*%+%-%?%(%)%%])", "\\%1")
    local root = vim.fn.getcwd()

    -- Ejecutar grep
    vim.fn.jobstart("grep -l -r \"" .. escaped_pattern .. "\" " .. root .. " --include=\"*.{js,ts,py,java,rb,php,go,rs,c,cpp,h,hpp,jsx,tsx}\" 2>/dev/null", {
      on_stdout = function(_, data)
        if data then
          for _, file in ipairs(data) do
            if file and file ~= "" then
              -- Verificar exclusiones
              local excluded = false
              for _, exclude in ipairs(M.config.exclude_patterns) do
                if file:match(exclude) then
                  excluded = true
                  break
                end
              end

              if not excluded then
                table.insert(found_files, file)
              end
            end
          end
        end
      end,
      on_exit = function()
        progress.update_spinner(spinner_id, "Buscando (" .. #found_files .. " coincidencias)")
        check_completion()
      end
    })
  end

  return found_files
end

-- Función para leer el contenido de los archivos identificados
function M.read_relevant_files(files, callback)
  local contents = {}

  -- Iniciar indicador de progreso
  local spinner_id = "read_files"
  progress.start_spinner(spinner_id, "Leyendo archivos relevantes (0/" .. #files .. ")", {
    style = "dots",
    position = "statusline"
  })

  for i, file in ipairs(files) do
    local content = file_utils.read_file(file)
    if content then
      -- Limitar tamaño del contenido
      if #content > M.config.max_file_size then
        content = content:sub(1, M.config.max_file_size) .. "\n... (contenido truncado)"
      end

      contents[file] = content
    end

    -- Actualizar progreso
    progress.update_spinner(spinner_id, "Leyendo archivos relevantes (" .. i .. "/" .. #files .. ")")
  end

  progress.stop_spinner(spinner_id, true)

  if callback then callback(contents) end
  return contents
end

-- Función para enriquecer el contexto con los archivos relevantes
function M.enrich_context(ticket_content, callback)
  -- Si no hay ticket, no podemos enriquecer
  if not ticket_content or ticket_content == "" then
    if callback then callback(false, "No hay contenido de ticket para analizar") end
    return
  end

  -- Paso 1: Analizar ticket para identificar archivos relevantes
  M.analyze_ticket_for_relevant_files(ticket_content, function(success, analysis)
    if not success then
      log.error("Error al analizar el ticket: " .. (analysis or "desconocido"))
      if callback then callback(false, "Error al analizar el ticket") end
      return
    end

    -- Paso 2: Buscar archivos según los patrones identificados
    M.search_relevant_files(analysis, function(success_files, files)
      if not success_files then
        log.error("Error al buscar archivos: " .. (files or "desconocido"))
        if callback then callback(false, "Error al buscar archivos") end
        return
      end

      -- Paso 3: Buscar con grep
      M.search_with_grep(analysis, function(success_grep)
        -- Paso 4: Leer contenido de los archivos identificados
        M.read_relevant_files(M.state.context_files, function(file_contents)
          -- Paso 5: Formatear contenido para el contexto
          local context_content = "## Archivos relevantes identificados automáticamente\n\n"

          if analysis.explanation then
            context_content = context_content .. "### Razón\n" .. analysis.explanation .. "\n\n"
          end

          -- Añadir contenido de cada archivo
          for file, content in pairs(file_contents) do
            context_content = context_content .. "### " .. file .. "\n"
            context_content = context_content .. "```\n"
            -- Mostrar solo una vista previa del archivo
            context_content = context_content .. content:sub(1, M.config.file_content_preview) .. "...\n"
            context_content = context_content .. "```\n\n"
          end

          -- Paso 6: Retornar el contexto enriquecido
          if callback then callback(true, context_content) end
        end)
      end)
    end)
  end)
end

-- Función principal: enriquecer el contexto actual
function M.enrich_current_context(callback)
  -- Obtener el contexto actual
  local paths = context.get_context_paths()
  local requirement = file_utils.read_file(paths.requirement) or ""

  -- Iniciar el enriquecimiento
  notify.info("Iniciando enriquecimiento de contexto con archivos relevantes...")

  -- Verificar el entorno antes de ejecutar operaciones asíncronas
  local utils_buffer = require("copilotchatassist.utils.buffer")
  if utils_buffer and vim.g.headless ~= true and not vim.in_fast_event() then
    log.debug("Entorno seguro para operaciones UI detectado")
  else
    log.warn("Entorno no óptimo para operaciones UI")
  end

  M.enrich_context(requirement, function(success, enriched_context)
    if not success then
      notify.error("Error al enriquecer contexto: " .. (enriched_context or "desconocido"))
      if callback then callback(false) end
      return
    end

    -- Añadir el contexto enriquecido a la síntesis
    local synthesis = file_utils.read_file(paths.synthesis) or ""
    synthesis = synthesis .. "\n\n" .. enriched_context

    -- Guardar la síntesis actualizada
    file_utils.write_file(paths.synthesis, synthesis)

    notify.success("Contexto enriquecido con " .. #M.state.context_files .. " archivos relevantes")

    if callback then callback(true) end
  end)
end

-- Comandos de Neovim
function M.create_commands()
  -- Proteger la creación de comandos
  local create_success, create_err = pcall(function()
    vim.api.nvim_create_user_command("CopilotContextEnrich", function()
      M.enrich_current_context()
    end, {
      desc = "Enriquecer el contexto actual con archivos relevantes"
    })
  end)

  if not create_success then
    log.error("Error al crear comando CopilotContextEnrich: " .. tostring(create_err))
  end

  vim.api.nvim_create_user_command("CopilotContextPreview", function()
    local paths = context.get_context_paths()
    local requirement = file_utils.read_file(paths.requirement) or ""

    M.analyze_ticket_for_relevant_files(requirement, function(success, analysis)
      if not success then
        notify.error("Error al analizar el ticket")
        return
      end

      -- Crear buffer con resultados de manera segura
      local buf = nil
      local create_buf_success, create_buf_err = pcall(function()
        buf = vim.api.nvim_create_buf(false, true)
      end)

      if not create_buf_success then
        log.error("Error al crear buffer: " .. tostring(create_buf_err))
        notify.error("Error al crear buffer de vista previa")
        return
      end

      local lines = {}

      table.insert(lines, "# Archivos relevantes identificados")
      table.insert(lines, "")

      if analysis.explanation then
        table.insert(lines, "## Explicación")
        table.insert(lines, analysis.explanation)
        table.insert(lines, "")
      end

      table.insert(lines, "## Patrones de archivos")
      for _, pattern in ipairs(analysis.file_patterns) do
        table.insert(lines, "- " .. pattern)
      end
      table.insert(lines, "")

      table.insert(lines, "## Patrones de búsqueda")
      for _, pattern in ipairs(analysis.grep_patterns) do
        table.insert(lines, "- " .. pattern)
      end
      table.insert(lines, "")

      if analysis.suggested_files and #analysis.suggested_files > 0 then
        table.insert(lines, "## Archivos sugeridos")
        for _, file in ipairs(analysis.suggested_files) do
          table.insert(lines, "- " .. file)
        end
      end

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      -- Abrir en split
      vim.cmd("vsplit")
      vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
    end)
  end, {
    desc = "Previsualizar archivos relevantes para el contexto actual"
  })
end

-- Inicializar el módulo
function M.setup(opts)
  local init_success, init_err = pcall(function()
    -- Aplicar opciones proporcionadas
    if opts then
      for k, v in pairs(opts) do
        M.config[k] = v
      end
    end

    -- Verificar entorno
    local safe_ui = true
    if vim.g.headless == true then
      log.warn("Módulo inicializado en modo headless, funcionalidad UI limitada")
      safe_ui = false
    end

    if vim.in_fast_event and vim.in_fast_event() then
      log.warn("Módulo inicializado en un evento asíncrono, funcionalidad UI limitada")
      safe_ui = false
    end

    -- Crear comandos solo si el entorno es seguro
    if safe_ui then
      M.create_commands()
    else
      log.info("Comandos de UI no creados debido a entorno no seguro")
    end

    log.info("Módulo de enriquecimiento de contexto inicializado")
  end)

  if not init_success then
    log.error("Error al inicializar módulo de enriquecimiento de contexto: " .. tostring(init_err))
    return false
  end

  return true
end

return M