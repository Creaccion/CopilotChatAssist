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
  vim.api.nvim_create_user_command("CopilotEnhancePR", function()
    require("copilotchatassist.pr_generator_i18n").enhance_pr()
  end, {
    desc = "Enhance current PR description using CopilotChat with multi-language support"
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

local function register_patches_commands()
  -- Patches commands
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

-- Register all plugin commands
local function create_commands()
  register_context_commands()
  register_todo_commands()
  register_pr_commands()
  register_documentation_commands()
  register_visualization_commands()
  register_patches_commands()
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

  -- Enable debug mode for log messages
  vim.g.copilotchatassist_debug = true

  -- Initialize documentation module - we do this completely lazily
  vim.defer_fn(function()
    pcall(function()
      local documentation = require("copilotchatassist.documentation")
      documentation.setup(opts.documentation or {})
    end)
  end, 100)

  -- Important initialization notification - show as a notification with timeout
  vim.notify("CopilotChatAssist initialized", vim.log.levels.INFO, { timeout = 2000 })
end

-- Expose get_copilotchat_config function for CopilotChat to use
function M.get_copilotchat_config()
  return options.get_copilotchat_config()
end

return M