local M = {}

-- Módulos requeridos
local options = require("copilotchatassist.options")
local log = require("copilotchatassist.utils.log")
local i18n = require("copilotchatassist.i18n")

-- Crear comandos del plugin
local function create_commands()
  -- Contexto y tickets
  vim.api.nvim_create_user_command("CopilotTicket", function()
    require("copilotchatassist.context").copilot_tickets()
  end, {})

  vim.api.nvim_create_user_command("CopilotUpdateContext", function()
    require("copilotchatassist.context").update_context()
  end, {})

  vim.api.nvim_create_user_command("CopilotProjectContext", function()
    require("copilotchatassist.context").get_project_context()
  end, {})

  -- TODOs
  vim.api.nvim_create_user_command("CopilotGenerateTodo", function()
    require("copilotchatassist.todos").generate_todo()
  end, {})

  vim.api.nvim_create_user_command("CopilotTodoSplit", function()
    require("copilotchatassist.todos").open_todo_split()
  end, {})

  -- PR y documentación
  vim.api.nvim_create_user_command("CopilotEnhancePR", function()
    require("copilotchatassist.pr_generator_i18n").enhance_pr()
  end, {
    desc = "Mejorar la descripción del PR actual usando CopilotChat con soporte multi-idioma"
  })

  vim.api.nvim_create_user_command("CopilotChangePRLanguage", function(opts)
    local target_language = opts.args
    if target_language == "" then
      -- Si no se especifica idioma, usar el idioma configurado
      target_language = i18n.get_current_language()
      vim.notify("Usando idioma configurado: " .. target_language, vim.log.levels.INFO)
    end
    require("copilotchatassist.pr_generator_i18n").change_pr_language(target_language)
  end, {
    desc = "Cambiar el idioma de la descripción del PR actual (english, spanish)",
    nargs = "?",
    complete = function()
      return {"english", "spanish"}
    end
  })

  -- Registrar también el comando simplificado
  vim.api.nvim_create_user_command("CopilotSimplePRLanguage", function(opts)
    local target_language = opts.args
    if target_language == "" then
      -- Si no se especifica idioma, usar el idioma configurado
      target_language = i18n.get_current_language()
      vim.notify("Usando idioma configurado: " .. target_language, vim.log.levels.INFO)
    end
    require("copilotchatassist.pr_generator_i18n").simple_change_pr_language(target_language)
  end, {
    desc = "Cambiar el idioma de la descripción del PR usando método simplificado (english, spanish)",
    nargs = "?",
    complete = function()
      return {"english", "spanish"}
    end
  })

  vim.api.nvim_create_user_command("CopilotAgentPR", function()
    require("copilotchatassist.agent_pr").agent_pr()
  end, {})

  vim.api.nvim_create_user_command("CopilotSynthetize", function()
    require("copilotchatassist.synthesize").synthesize()
  end, {})

  vim.api.nvim_create_user_command("CopilotStructure", function()
    require("copilotchatassist.structure").structure()
  end, {})

  vim.api.nvim_create_user_command("CopilotDocReview", function()
    require("copilotchatassist.doc_review").doc_review()
  end, {})

  vim.api.nvim_create_user_command("CopilotDocChanges", function()
    require("copilotchatassist.doc_changes").doc_changes()
  end, {})

  vim.api.nvim_create_user_command("CopilotDocGitChanges", function()
    require("copilotchatassist.documentation.copilot_git_diff").document_modified_elements()
  end, {
    desc = "Documentar elementos modificados según diff de git (local o via CopilotChat)"
  })

  vim.api.nvim_create_user_command("CopilotDot", function()
    require("copilotchatassist.dot").dot()
  end, {})

  vim.api.nvim_create_user_command("CopilotDotPreview", function()
    require("copilotchatassist.dot_preview").dot_preview()
  end, {})

  -- Comandos para patches (migrados desde CopilotFiles)
  vim.api.nvim_create_user_command("CopilotPatchesWindow", function()
    require("copilotchatassist.patches").show_patch_window()
  end, {})

  vim.api.nvim_create_user_command("CopilotPatchesShowQueue", function()
    require("copilotchatassist.patches").show_patch_queue()
  end, {})

  vim.api.nvim_create_user_command("CopilotPatchesApply", function()
    require("copilotchatassist.patches").apply_patch_queue()
  end, {})

  vim.api.nvim_create_user_command("CopilotPatchesClearQueue", function()
    require("copilotchatassist.patches").clear_patch_queue()
  end, {})

  vim.api.nvim_create_user_command("CopilotPatchesProcessBuffer", function()
    require("copilotchatassist.patches").process_current_buffer()
  end, {})

  -- Comandos para asistencia de documentación
  vim.api.nvim_create_user_command("CopilotDocScan", function()
    require("copilotchatassist.documentation").scan_buffer()
  end, {
    desc = "Escanear el buffer actual para detectar elementos sin documentación"
  })

  vim.api.nvim_create_user_command("CopilotDocSync", function()
    require("copilotchatassist.documentation").sync_doc()
  end, {
    desc = "Sincronizar la documentación (actualizar o generar)"
  })

  vim.api.nvim_create_user_command("CopilotDocGenerate", function()
    require("copilotchatassist.documentation").generate_doc_at_cursor()
  end, {
    desc = "Generar documentación para el elemento en la posición del cursor"
  })

  -- El comando especial para documentar records de Java ahora está obsoleto
  -- ya que la funcionalidad ha sido integrada en los comandos principales
  -- Lo mantenemos por compatibilidad con versiones anteriores
  vim.api.nvim_create_user_command("CopilotDocJavaRecord", function()
    vim.notify("Este comando está obsoleto. Usa CopilotDocSync o CopilotDocGenerate que ahora detectan automáticamente los records de Java.", vim.log.levels.WARN)
    require("copilotchatassist.documentation.language.java").document_java_record()
  end, {})
end

-- Configuración del plugin
function M.setup(opts)
  -- Aplicar opciones personalizadas
  options.set(opts or {})

  -- Configurar nivel de log
  if options.get().log_level then
    vim.fn.setenv("COPILOTCHATASSIST_LOG_LEVEL", options.get().log_level)
  end

  -- Registrar comandos inmediatamente
  create_commands()

  -- Cargar comandos de depuración
  pcall(function()
    local debug_commands = require("copilotchatassist.commands")
    debug_commands.setup()
  end)

  -- Inicializar submódulos (después de registrar comandos)
  pcall(function()
    local patches = require("copilotchatassist.patches")
    patches.setup()
  end)

  -- Activar modo de depuración para los mensajes de log
  vim.g.copilotchatassist_debug = true

  -- Inicializar el módulo de documentación - lo hacemos de manera totalmente perezosa
  vim.defer_fn(function()
    pcall(function()
      local documentation = require("copilotchatassist.documentation")
      documentation.setup(opts.documentation or {})
    end)
  end, 100)

  log.info("CopilotChatAssist inicializado correctamente")
end

-- Exponer la función get_copilotchat_config para que CopilotChat pueda utilizarla
function M.get_copilotchat_config()
  return options.get_copilotchat_config()
end

return M