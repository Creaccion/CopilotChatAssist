-- Module to store and retrieve CopilotChatAssist options

local M = {
  context_dir = vim.fn.expand("~/.copilot_context"),
  model = "gpt-4.1",
  temperature = 0.1,
  log_level = vim.log.levels.INFO,
  language = "english",
  code_language = "english",
  todo_split_orientation = "vertical",
  todo_split_width = 50,
  todo_split_height = 30,
  code_review_window_orientation = "vertical",
  code_review_window_width = 50,
  code_review_window_height = 30,
  code_review_keep_window_open = true,
  notification_level = vim.log.levels.INFO,       -- Nivel de las notificaciones normales
  notification_timeout = 2000,                    -- Tiempo de las notificaciones en ms
  success_notification_level = vim.log.levels.INFO, -- Nivel para notificaciones de éxito
  silent_mode = false,                            -- Si es true, reduce el número de notificaciones
  use_progress_indicator = true,                  -- Si es true, muestra indicadores de progreso para operaciones largas
  progress_indicator_style = "dots",              -- Estilo del spinner: dots, line, braille, circle, moon, arrow, bar

  -- Configuración para integración con Jira
  jira = {
    host = nil,             -- URL de la instancia Jira (ej: "https://tuempresa.atlassian.net")
    email = nil,            -- Email de la cuenta Jira
    api_token = nil,        -- Token API de Jira (https://id.atlassian.com/manage-profile/security/api-tokens)
    project_key = nil,      -- Clave del proyecto por defecto (ej: "PROJ")
    auto_load = true,       -- Cargar automáticamente ticket al cambiar de rama
    auto_update = false,    -- Actualizar Jira automáticamente al guardar contexto
    use_keyring = true,     -- Usar el llavero del sistema para guardar credenciales
    cache_timeout = 300,    -- Tiempo de caché en segundos (5 minutos)
    request_timeout = 10,   -- Tiempo máximo para peticiones HTTP en segundos
    max_results = 20,       -- Número máximo de resultados para búsquedas
    context_format = "detailed" -- Formato del contexto extraído: "simple", "detailed"
  }
}

-- Default highlight groups for TODO priorities (can be overridden by user)
M.todo_highlights = {
  [1] = "CopilotTodoPriority1",
  [2] = "CopilotTodoPriority2",
  [3] = "CopilotTodoPriority3",
  [4] = "CopilotTodoPriority4",
  [5] = "CopilotTodoPriority5",
}

-- Setup default highlights if not already defined
vim.api.nvim_command('highlight default CopilotTodoPriority1 guifg=#ff5555 gui=bold')
vim.api.nvim_command('highlight default CopilotTodoPriority2 guifg=#ffaf00 gui=bold')
vim.api.nvim_command('highlight default CopilotTodoPriority3 guifg=#ffd700 gui=bold')
vim.api.nvim_command('highlight default CopilotTodoPriority4 guifg=#61afef gui=bold')
vim.api.nvim_command('highlight default CopilotTodoPriority5 guifg=#888888 gui=italic')

function M.set(opts)
  for k, v in pairs(opts) do
    M[k] = v
  end
end

function M.apply(opts)
  M.set(opts or {})
end

function M.get()
  return M
end

function M.get_copilotchat_config()
  local config = {
    model = M.model,
    temperature = M.temperature,       -- Lower = focused, higher = creative
    system_prompt = require("copilotchatassist.prompts.system").default,
    show_notification = false,         -- Disable CopilotChat notifications
    window = {
      layout = "horizontal",
      width = 150,
      height = 20,
      border = "rounded",
      title = "🤖 AI Assistant",
      zindex = 100,
    },
  }

  -- Pasar el contexto almacenado globalmente como prompt inicial si está disponible
  if vim.g.copilotchatassist_context then
    -- Agregar callback para inicializar con el contexto
    config.init = function(chat)
      -- Esperar un tick para asegurar que CopilotChat esté completamente inicializado
      vim.defer_fn(function()
        local CopilotChat = require("CopilotChat")
        if CopilotChat and CopilotChat.ask then
          -- Usar el contexto almacenado
          CopilotChat.ask(vim.g.copilotchatassist_context)
        end
      end, 100)
    end
  end

  return config
end

return M