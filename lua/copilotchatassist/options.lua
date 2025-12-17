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
  return {
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
end

return M