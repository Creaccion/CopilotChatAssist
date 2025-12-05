-- Wrapper for CopilotChat API integration

local options = require("copilotchatassist.options")
local utils = require("copilotchatassist.utils")
local string_utils = require("copilotchatassist.utils.string")
local log = require("copilotchatassist.utils.log")

local M = {}

-- Historial de solicitudes para referencia
M.history = {
  requests = {},
  responses = {},
  max_history = 50
}

-- Agregar entrada al historial
local function add_to_history(request, response)
  if #M.history.requests >= M.history.max_history then
    table.remove(M.history.requests, 1)
    table.remove(M.history.responses, 1)
  end

  table.insert(M.history.requests, request)
  table.insert(M.history.responses, response)
end

-- Función principal para enviar peticiones a CopilotChat
function M.ask(message, opts)
  opts = opts or {}
  if not opts.system_prompt then
    opts.system_prompt = options.get().system_prompt or
        require("copilotchatassist.prompts.system").default
  end

  -- Registrar la solicitud sin usar el módulo log
  -- Mensaje debug silenciado para evitar error
  -- vim.notify("Sending request to CopilotChat", vim.log.levels.DEBUG)

  -- Si se proporciona una función de callback, envolvemos la original para almacenar el historial
  local original_callback = opts.callback
  if opts.callback and type(opts.callback) == "function" then
    opts.callback = function(response)
      add_to_history(message, response)
      original_callback(response)
    end
  end

  local ok, CopilotChat = pcall(require, "CopilotChat")
  if ok and CopilotChat and type(CopilotChat.ask) == "function" then
    local success = pcall(function()
      CopilotChat.ask(message, opts)
    end)
    if not success then
      vim.notify("Error al llamar a CopilotChat.ask directamente, intentando con comando", vim.log.levels.WARN)
      vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
      -- No podemos registrar la respuesta si usamos el comando
    end
  else
    vim.notify("Usando comando CopilotChat", vim.log.levels.INFO)
    vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
    -- No podemos registrar la respuesta si usamos el comando
  end
end

-- Abrir CopilotChat con contexto específico
function M.open(context, opts)
  opts = opts or {}
  if not opts.system_prompt then
    opts.system_prompt = require("copilotchatassist.prompts.system").default
  end

  -- Registrar la solicitud sin usar el módulo log
  -- Mensaje debug silenciado para evitar error
  -- vim.notify("Opening CopilotChat with context", vim.log.levels.DEBUG)

  local ok, CopilotChat = pcall(require, "CopilotChat")
  if ok and CopilotChat and type(CopilotChat.open) == "function" then
    local success = pcall(function()
      CopilotChat.open({ context = context }, opts)
    end)
    if not success then
      vim.notify("Error al abrir CopilotChat con contexto, intentando con comando", vim.log.levels.WARN)
      vim.cmd("CopilotChat " .. vim.fn.shellescape(context))
    end
  else
    vim.cmd("CopilotChat " .. vim.fn.shellescape(context))
  end
end

-- Solicitar asistencia con TODOs
function M.ask_todo_assistance(todo_content, callback)
  local prompt = [[
Por favor, ayúdame a organizar mejor estas tareas TODO:

```
]] .. todo_content .. [[
```

Necesito que:
1. Identifiques tareas duplicadas o similares y sugiere consolidarlas
2. Asegures que todas las tareas tienen prioridades adecuadas (1-5)
3. Recomiendes un mejor orden de ejecución basado en dependencias
4. Sugieras estados adecuados (pending, in_progress, done)
5. Identifiques tareas que podrían dividirse en subtareas más manejables

Responde con la tabla markdown mejorada.
]]

  M.ask(prompt, {
    headless = true,
    callback = function(response)
      if callback then
        callback(response)
      end
    end
  })
end

-- Obtener sugerencias para próximas tareas basadas en las actuales
function M.suggest_next_tasks(current_tasks, callback)
  local tasks_str = ""
  for _, task in ipairs(current_tasks) do
    tasks_str = tasks_str .. "- [" .. task.status .. "] " .. task.title .. "\n"
  end

  local prompt = [[
Basado en estas tareas actuales:

]] .. tasks_str .. [[

Por favor, sugiere 3-5 tareas adicionales que serían útiles para completar este proyecto.
Para cada tarea sugerida, proporciona:
1. Un título breve y claro
2. Una prioridad recomendada (1-5, siendo 1 la más alta)
3. Una breve justificación de por qué esta tarea es importante

Formatea tu respuesta como una tabla markdown con columnas: Título | Prioridad | Justificación
]]

  M.ask(prompt, {
    headless = true,
    callback = function(response)
      if callback then
        callback(response)
      end
    end
  })
end

-- Solicitar a CopilotChat una explicación sobre una tarea específica
function M.explain_task(task, callback)
  local prompt = [[
Necesito comprender mejor la siguiente tarea:

- Título: ]] .. task.title .. [[
- Descripción: ]] .. (task.description or "N/A") .. [[
- Categoría: ]] .. (task.category or "N/A") .. [[
- Prioridad: ]] .. (task.priority or "N/A") .. [[

Por favor, ayúdame con:
1. Una explicación detallada de lo que implica esta tarea
2. Posibles retos o consideraciones importantes
3. Recursos o conocimientos que podría necesitar
4. Cómo se relaciona con otras tareas o componentes del proyecto
]]

  M.ask(prompt, {
    headless = false,  -- Mostrar la respuesta en la UI
    callback = function(response)
      if callback then
        callback(response)
      end
    end
  })
end

-- Obtener historial de solicitudes recientes
function M.get_history(limit)
  limit = limit or M.history.max_history
  local result = {}

  local count = math.min(limit, #M.history.requests)
  for i = #M.history.requests - count + 1, #M.history.requests do
    table.insert(result, {
      request = M.history.requests[i],
      response = M.history.responses[i]
    })
  end

  return result
end

return M