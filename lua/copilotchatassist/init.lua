local M = {}

-- Required modules
local options = require("copilotchatassist.options")
local log = require("copilotchatassist.utils.log")
local i18n = require("copilotchatassist.i18n")

-- Group commands by functionality for better organization
local function register_context_commands()
  -- Context and tickets
  vim.api.nvim_create_user_command("CopilotTicket", function()
    require("copilotchatassist.context").copilot_tickets()
  end, {
    desc = "Open or generate context for the current ticket/branch"
  })

  vim.api.nvim_create_user_command("CopilotUpdateContext", function()
    require("copilotchatassist.context").update_context()
  end, {
    desc = "Update existing context files with recent changes"
  })

  vim.api.nvim_create_user_command("CopilotProjectContext", function()
    require("copilotchatassist.context").get_project_context()
  end, {
    desc = "Generate or update project-level context"
  })

  vim.api.nvim_create_user_command("CopilotSynthetize", function()
    require("copilotchatassist.synthesize").synthesize()
  end, {
    desc = "Create a comprehensive synthesis of the current project"
  })
end

local function register_todo_commands()
  -- TODOs management
  vim.api.nvim_create_user_command("CopilotGenerateTodo", function()
    require("copilotchatassist.todos").generate_todo()
  end, {
    desc = "Generate TODOs from requirements or context"
  })

  vim.api.nvim_create_user_command("CopilotTodoSplit", function()
    require("copilotchatassist.todos").open_todo_split()
  end, {
    desc = "Open TODOs in a split window"
  })
end

local function register_pr_commands()
  -- PR management commands
  vim.api.nvim_create_user_command("CopilotEnhancePR", function(opts)
    local pr_module = require("copilotchatassist.pr_generator_i18n")

    -- Obtener opciones del comando
    local options = {}

    -- Por defecto, actualizar título y mostrar vista previa
    options.update_title = true

    -- Si se especificó --no-preview, desactivar vista previa
    if opts.fargs and vim.tbl_contains(opts.fargs, "--no-preview") then
      options.use_preview = false
    else
      options.use_preview = true
    end

    -- Si se especificó --no-title-update, no actualizar título
    if opts.fargs and vim.tbl_contains(opts.fargs, "--no-title-update") then
      options.update_title = false
    end

    pr_module.enhance_pr(options)
  end, {
    desc = "Enhance current PR description with preview, updates title with Jira ticket",
    nargs = "*",
    complete = function()
      return {"--no-preview", "--no-title-update"}
    end
  })

  vim.api.nvim_create_user_command("CopilotChangePRLanguage", function(opts)
    local target_language = opts.args
    if target_language == "" then
      -- If no language specified, use configured language
      target_language = i18n.get_current_language()
      log.debug("Using configured language: " .. target_language)
    end
    require("copilotchatassist.pr_generator_i18n").change_pr_language(target_language)
  end, {
    desc = "Change the language of the current PR description (english, spanish)",
    nargs = "?",
    complete = function()
      return {"english", "spanish"}
    end
  })

  vim.api.nvim_create_user_command("CopilotSimplePRLanguage", function(opts)
    local target_language = opts.args
    if target_language == "" then
      -- If no language specified, use configured language
      target_language = i18n.get_current_language()
      log.debug("Using configured language: " .. target_language)
    end
    require("copilotchatassist.pr_generator_i18n").simple_change_pr_language(target_language)
  end, {
    desc = "Change PR description language using simplified method (english, spanish)",
    nargs = "?",
    complete = function()
      return {"english", "spanish"}
    end
  })

  -- Comando para corregir diagramas Mermaid en la descripción de PR
  vim.api.nvim_create_user_command("CopilotFixPRDiagrams", function()
    require("copilotchatassist.pr_generator_i18n").fix_mermaid_diagrams()
  end, {
    desc = "Fix Mermaid diagrams in PR description with proper syntax"
  })

  -- Command for direct emergency PR update from saved response
  -- Command to reset any stuck PR operations
  vim.api.nvim_create_user_command("CopilotResetPROperations", function()
    local pr_module = require("copilotchatassist.pr_generator_i18n")
    pr_module.force_reset_pr_operations()
  end, {
    desc = "Reset the state of stuck PR operations"
  })

  -- Comando para actualización ultra-directa desde la respuesta en formato crudo
  vim.api.nvim_create_user_command("CopilotSuperDirectPRUpdate", function(opts)
    local log = require("copilotchatassist.utils.log")
    local notify = require("copilotchatassist.utils.notify")
    local pr_module = require("copilotchatassist.pr_generator_i18n")

    log.info("Iniciando actualización ultra directa desde archivo de respuesta raw")
    notify.info("Iniciando actualización ultra directa del PR...")

    -- Leer el archivo de respuesta raw guardado
    local cache_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    local response_file = cache_dir .. "/enhance_pr_raw_table.txt"

    local f = io.open(response_file, "r")
    if not f then
      log.error("No se encontró archivo de respuesta raw para actualización ultra directa")
      notify.error("No se encontró archivo de respuesta raw guardado")
      return false
    end

    local content = f:read("*a")
    f:close()

    log.debug("Archivo de respuesta raw leído correctamente, tamaño: " .. #content)

    -- Construir una tabla desde el contenido leído
    local success, response_table = pcall(function()
      -- Extraer contenido de la tabla usando el formato más simple posible
      local content_field = content:match('content = "(.-)",')
      if not content_field then
        log.error("No se pudo extraer content del archivo de respuesta raw")
        return nil
      end

      -- Reemplazar secuencias de escape sin procesamiento complejo
      local clean_content = content_field:gsub("\\n", "\n")

      -- Crear una tabla simple con el contenido extraído
      return { content = clean_content }
    end)

    if not success or not response_table then
      log.error("Error al procesar el archivo de respuesta raw")
      notify.error("Formato de archivo de respuesta raw no reconocido")
      return false
    end

    -- Opciones
    local use_preview = true
    if opts.fargs and vim.tbl_contains(opts.fargs, "--no-preview") then
      use_preview = false
    end

    -- Usar la función compartida ultra_direct_update con actualización de título y opción de vista previa
    local update_success = pr_module.ultra_direct_update(response_table, true, use_preview)

    if update_success then
      notify.success("PR actualizado exitosamente con método ultra directo")
      return true
    else
      notify.error("Error al actualizar PR con método ultra directo")
      return false
    end
  end, {
    desc = "Actualizar PR directamente desde archivo de respuesta raw con vista previa",
    nargs = "*",
    complete = function()
      return {"--no-preview"}
    end
  })

  vim.api.nvim_create_user_command("CopilotEmergencyPRUpdate", function()
    -- Function to directly update PR using saved response file
    local function emergency_direct_update()
      local log = require("copilotchatassist.utils.log")
      local notify = require("copilotchatassist.utils.notify")

      log.info("Starting emergency direct update from saved response file")
      notify.info("Starting direct emergency PR update...")

      -- Reset any stuck state
      local pr_module = require("copilotchatassist.pr_generator_i18n")
      pr_module.pr_generation_in_progress = false
      pr_module.pr_update_in_progress = false

      -- Try to read directly from saved response file
      local cache_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
      local response_file = cache_dir .. "/pr_immediate_response.txt"

      local f = io.open(response_file, "r")
      if not f then
        log.error("Could not find response file for emergency update")
        notify.error("No saved response file found")
        return false
      end

      local content = f:read("*a")
      f:close()

      log.debug("Response file read successfully, size: " .. #content)

      -- Extract content from table structure
      local extracted_content = content:match('content = "(.-)",')
      if not extracted_content then
        log.error("Could not extract content from saved response")
        notify.error("Unrecognized response file format")
        return false
      end

      log.debug("Content extracted successfully, length: " .. #extracted_content)

      -- Replace escape sequences
      local clean_content = extracted_content:gsub("\\n", "\n")
      log.debug("Escape sequences replaced, length: " .. #clean_content)

      -- Save content to temporary file
      local tmpfile = "/tmp/copilot_emergency_pr_update_" .. os.time() .. ".md"
      local tmp_f = io.open(tmpfile, "w")
      if not tmp_f then
        log.error("Error creating temporary file: " .. tmpfile)
        notify.error("Error creating temporary file")
        return false
      end

      tmp_f:write(clean_content)
      tmp_f:close()

      log.debug("Content written to temporary file: " .. tmpfile)

      -- Execute gh command to update PR
      local cmd = string.format("gh pr edit --body-file '%s'", tmpfile)
      log.debug("Executing command: " .. cmd)

      local success = os.execute(cmd)
      if success == 0 or success == true then
        log.info("PR successfully updated with direct emergency method")
        notify.success("PR successfully updated with emergency method")
        return true
      else
        log.error("Error updating PR: " .. tostring(success))
        notify.error("Error updating PR, code: " .. tostring(success))
        return false
      end
    end

    emergency_direct_update()
  end, {
    desc = "Update PR directly from saved response file (emergency)"
  })
end

local function register_documentation_commands()
  -- Documentation commands
  vim.api.nvim_create_user_command("CopilotDocReview", function()
    require("copilotchatassist.doc_review").doc_review()
  end, {
    desc = "Review documentation in current buffer"
  })

  vim.api.nvim_create_user_command("CopilotDocChanges", function()
    require("copilotchatassist.doc_changes").doc_changes()
  end, {
    desc = "Document changes made in current buffer"
  })

  vim.api.nvim_create_user_command("CopilotDocGitChanges", function()
    require("copilotchatassist.documentation.copilot_git_diff").document_modified_elements()
  end, {
    desc = "Document elements modified according to git diff (local or via CopilotChat)"
  })

  vim.api.nvim_create_user_command("CopilotDocScan", function()
    require("copilotchatassist.documentation").scan_buffer()
  end, {
    desc = "Scan current buffer to detect elements without documentation"
  })

  vim.api.nvim_create_user_command("CopilotDocSync", function()
    require("copilotchatassist.documentation").sync_doc()
  end, {
    desc = "Synchronize documentation (update or generate)"
  })

  vim.api.nvim_create_user_command("CopilotDocGenerate", function()
    require("copilotchatassist.documentation").generate_doc_at_cursor()
  end, {
    desc = "Generate documentation for element at cursor position"
  })

  -- Deprecated command, kept for backward compatibility
  vim.api.nvim_create_user_command("CopilotDocJavaRecord", function()
    log.warn("This command is deprecated. Use CopilotDocSync or CopilotDocGenerate which now automatically detect Java records.")
    require("copilotchatassist.documentation.language.java").document_java_record()
  end, {
    desc = "DEPRECATED: Document Java record (use CopilotDocSync instead)"
  })
end

local function register_visualization_commands()
  -- Visualization commands
  vim.api.nvim_create_user_command("CopilotStructure", function()
    require("copilotchatassist.structure").structure()
  end, {
    desc = "Generate project structure overview"
  })

  vim.api.nvim_create_user_command("CopilotDot", function()
    require("copilotchatassist.dot").dot()
  end, {
    desc = "Generate DOT graph visualization"
  })

  vim.api.nvim_create_user_command("CopilotDotPreview", function()
    require("copilotchatassist.dot_preview").dot_preview()
  end, {
    desc = "Preview DOT graph visualization"
  })
end

local function register_code_review_commands()
  -- Comandos para Code Review
  vim.api.nvim_create_user_command("CopilotCodeReview", function()
    require("copilotchatassist.code_review").start_review()
  end, {
    desc = "Iniciar Code Review de los cambios en Git diff"
  })

  vim.api.nvim_create_user_command("CopilotCodeReviewList", function()
    require("copilotchatassist.code_review").show_review_comments()
  end, {
    desc = "Mostrar lista de comentarios del Code Review"
  })

  vim.api.nvim_create_user_command("CopilotCodeReviewStats", function()
    require("copilotchatassist.code_review").show_review_stats()
  end, {
    desc = "Mostrar estadísticas del Code Review actual"
  })

  vim.api.nvim_create_user_command("CopilotCodeReviewExport", function(opts)
    local path = opts.args ~= "" and opts.args or nil
    require("copilotchatassist.code_review").export_review(path)
  end, {
    desc = "Exportar Code Review a archivo JSON",
    nargs = "?"
  })

  vim.api.nvim_create_user_command("CopilotCodeReviewReanalyze", function()
    require("copilotchatassist.code_review").reanalyze_diff()
  end, {
    desc = "Re-analizar cambios en el diff para actualizar estado de comentarios"
  })

  vim.api.nvim_create_user_command("CopilotCodeReviewReset", function()
    require("copilotchatassist.code_review").reset_review()
  end, {
    desc = "Reiniciar/limpiar la revisión de código actual"
  })
end

local function register_patches_commands()
  -- Comandos para patches (migrados desde CopilotFiles)
  vim.api.nvim_create_user_command("CopilotPatchesWindow", function()
    require("copilotchatassist.patches").show_patch_window()
  end, {
    desc = "Show patches window"
  })

  vim.api.nvim_create_user_command("CopilotPatchesShowQueue", function()
    require("copilotchatassist.patches").show_patch_queue()
  end, {
    desc = "Show current patch queue"
  })

  vim.api.nvim_create_user_command("CopilotPatchesApply", function()
    require("copilotchatassist.patches").apply_patch_queue()
  end, {
    desc = "Apply patches in queue"
  })

  vim.api.nvim_create_user_command("CopilotPatchesClearQueue", function()
    require("copilotchatassist.patches").clear_patch_queue()
  end, {
    desc = "Clear patch queue"
  })

  vim.api.nvim_create_user_command("CopilotPatchesProcessBuffer", function()
    require("copilotchatassist.patches").process_current_buffer()
  end, {
    desc = "Process current buffer for patches"
  })
end

local function register_log_commands()
  -- Comando para configurar nivel de log
  vim.api.nvim_create_user_command("CopilotLog", function(opts)
    local log_level = string.upper(opts.args)
    local log_module = require("copilotchatassist.utils.log")

    -- Establecer nivel de log
    if log_level == "DEBUG" then
      options.set({ log_level = vim.log.levels.DEBUG })
      vim.g.copilotchatassist_debug = true
      log.info("Nivel de log establecido a DEBUG")
    elseif log_level == "TRACE" then
      options.set({ log_level = vim.log.levels.TRACE })
      vim.g.copilotchatassist_debug = true
      log.info("Nivel de log establecido a TRACE")
    elseif log_level == "INFO" then
      options.set({ log_level = vim.log.levels.INFO })
      vim.g.copilotchatassist_debug = false
      log.info("Nivel de log establecido a INFO")
    elseif log_level == "WARN" or log_level == "WARNING" then
      options.set({ log_level = vim.log.levels.WARN })
      vim.g.copilotchatassist_debug = false
      log.info("Nivel de log establecido a WARN")
    elseif log_level == "ERROR" then
      options.set({ log_level = vim.log.levels.ERROR })
      vim.g.copilotchatassist_debug = false
      log.info("Nivel de log establecido a ERROR")
    elseif log_level == "STATUS" or log_level == "SHOW" or log_level == "" then
      log_module.show_config()
    else
      log.info("Uso: CopilotLog [DEBUG|TRACE|INFO|WARN|ERROR|STATUS]")
    end
  end, {
    desc = "Establecer nivel de log o mostrar estado",
    nargs = "?",
    complete = function()
      return {"DEBUG", "TRACE", "INFO", "WARN", "ERROR", "STATUS"}
    end
  })

  -- El comando especial para documentar records de Java ahora está obsoleto
  -- ya que la funcionalidad ha sido integrada en los comandos principales
  -- Lo mantenemos por compatibilidad con versiones anteriores
  vim.api.nvim_create_user_command("CopilotDocJavaRecord", function()
    log.warn("Este comando está obsoleto. Usa CopilotDocSync o CopilotDocGenerate que ahora detectan automáticamente los records de Java.")
    require("copilotchatassist.documentation.language.java").document_java_record()
  end, {})
end

-- Plugin configuration
function M.setup(opts)
  -- Apply custom options
  options.set(opts or {})

  -- Configure log level
  if options.get().log_level then
    vim.fn.setenv("COPILOTCHATASSIST_LOG_LEVEL", options.get().log_level)
  end

  -- Register commands immediately
  local function create_commands()
    register_context_commands()
    register_todo_commands()
    register_pr_commands()
    register_documentation_commands()
    register_visualization_commands()
    register_code_review_commands()
    register_patches_commands()
    register_log_commands()
  end

  create_commands()

  -- Load debug commands
  pcall(function()
    local debug_commands = require("copilotchatassist.commands")
    debug_commands.setup()
  end)

  -- Initialize submodules (after registering commands)
  pcall(function()
    local patches = require("copilotchatassist.patches")
    patches.setup()
  end)

  -- Inicializar sistema de progreso visual
  pcall(function()
    local progress = require("copilotchatassist.utils.progress")
    progress.setup()
  end)

  -- Inicializar sistema de manejo de contexto para CopilotChat
  pcall(function()
    local context_handler = require("copilotchatassist.utils.context_handler")
    context_handler.setup()
  end)

  -- Inicializar enriquecedor de contexto
  pcall(function()
    local context_enricher = require("copilotchatassist.context_enricher")
    context_enricher.setup()
  end)

  -- Inicializar gestor de estado
  pcall(function()
    local state_manager = require("copilotchatassist.utils.state_manager")
    state_manager.setup()
  end)

  -- Respetar la configuración de log_level en lugar de forzar modo debug
  -- Solo establecer modo debug si el nivel es DEBUG o superior
  local user_opts = opts or {}
  if user_opts.log_level == nil or user_opts.log_level >= vim.log.levels.DEBUG then
    vim.g.copilotchatassist_debug = true
  else
    vim.g.copilotchatassist_debug = false
  end
  vim.g.copilotchatassist_silent = true

  -- Initialize documentation module - we do this completely lazily
  vim.defer_fn(function()
    pcall(function()
      local documentation = require("copilotchatassist.documentation")
      documentation.setup((opts or {}).documentation or {})
    end)
  end, 100)

  -- Log initialization but don't show notification
  local log = require("copilotchatassist.utils.log")
  log.info("CopilotChatAssist initialized")
end

-- Expose get_copilotchat_config function for CopilotChat to use
function M.get_copilotchat_config()
  return options.get_copilotchat_config()
end

return M