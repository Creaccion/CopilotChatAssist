local M = {}

-- Módulos requeridos
local options = require("copilotchatassist.options")
local log = require("copilotchatassist.utils.log")

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
    require("copilotchatassist.pr_generator").enhance_pr()
  end, {})

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

  -- Inicializar submódulos (después de registrar comandos)
  pcall(function()
    local patches = require("copilotchatassist.patches")
    patches.setup()
  end)

  log.info("CopilotChatAssist inicializado correctamente")
end

-- Exponer la función get_copilotchat_config para que CopilotChat pueda utilizarla
function M.get_copilotchat_config()
  return options.get_copilotchat_config()
end

return M