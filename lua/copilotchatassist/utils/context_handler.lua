-- Módulo para manejar contexto entre CopilotChatAssist y CopilotChat
local M = {}
local log = require("copilotchatassist.utils.log")

-- Guarda el contexto para que esté disponible para CopilotChat
function M.store_context(context)
  if not context or type(context) ~= "string" or context == "" then
    log.debug("Intento de guardar contexto vacío o inválido, ignorando")
    return false
  end

  -- Guardar contexto globalmente
  vim.g.copilotchatassist_context = context
  log.debug("Contexto guardado globalmente (" .. #context .. " bytes)")
  return true
end

-- Recupera el contexto guardado
function M.get_stored_context()
  return vim.g.copilotchatassist_context
end

-- Aplica el contexto guardado a una instancia de CopilotChat
function M.apply_context_to_chat()
  local context = M.get_stored_context()

  if not context or context == "" then
    log.debug("No hay contexto disponible para aplicar a CopilotChat")
    return false
  end

  -- Intentar cargar CopilotChat
  local ok, CopilotChat = pcall(require, "CopilotChat")
  if not ok or not CopilotChat then
    log.debug("No se pudo cargar CopilotChat para aplicar contexto")
    return false
  end

  -- Comprobar si CopilotChat tiene el método ask
  if type(CopilotChat.ask) ~= "function" then
    log.debug("CopilotChat.ask no es una función, no se puede aplicar contexto")
    return false
  end

  -- Aplicar contexto a CopilotChat
  vim.defer_fn(function()
    CopilotChat.ask(context)
    log.debug("Contexto aplicado a CopilotChat correctamente")
  end, 100) -- Pequeño retraso para asegurar que CopilotChat esté inicializado

  return true
end

-- Registrar un autocomando para aplicar contexto cuando CopilotChat se abre
function M.setup()
  -- Crear autocomando para cuando se abre un buffer de CopilotChat
  vim.api.nvim_create_autocmd({"BufEnter"}, {
    pattern = "*copilot-chat*",
    callback = function()
      -- Verificar si ya tenemos contexto guardado
      if M.get_stored_context() then
        -- Esperar un momento para que CopilotChat esté completamente inicializado
        vim.defer_fn(function()
          M.apply_context_to_chat()
        end, 200)
      end
    end,
    group = vim.api.nvim_create_augroup("CopilotChatAssistContextHandler", { clear = true })
  })

  log.debug("Autocomando para manejo de contexto en CopilotChat registrado")
end

return M