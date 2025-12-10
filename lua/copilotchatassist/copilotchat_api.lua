-- Simplified wrapper for CopilotChat API integration
-- This version delegates more functionality to CopilotChat and eliminates duplicated code

local options = require("copilotchatassist.options")
local log = require("copilotchatassist.utils.log")
local string_utils = require("copilotchatassist.utils.string")

local M = {}

-- Process copilot response for patches
local function process_response(response)
  if response and type(response) == "string" then
    local patches_module = require("copilotchatassist.patches")
    local patch_count = patches_module.process_copilot_response(response)

    if patch_count > 0 then
      vim.defer_fn(function()
        log.info({
          english = string.format("Found %d patches in the response. Use :CopilotPatchesWindow to view them.", patch_count),
          spanish = string.format("Se encontraron %d patches en la respuesta. Usa :CopilotPatchesWindow para verlos.", patch_count)
        })
      end, 500)
    end

    return patch_count
  end

  return 0
end

-- Save debug information
local function save_debug_info(message, type, content)
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")

  local filename = type and debug_dir .. "/" .. type .. ".txt" or debug_dir .. "/last_prompt.txt"
  local file = io.open(filename, "w")

  if file then
    file:write(content or message)
    file:close()
    log.debug({
      english = "Debug info saved to " .. filename,
      spanish = "Información de depuración guardada en " .. filename
    })
  end
end

-- Main function for sending requests to CopilotChat
function M.ask(message, opts)
  opts = opts or {}
  if not opts.system_prompt then
    opts.system_prompt = options.get().system_prompt or
      require("copilotchatassist.prompts.system").default
  end

  -- Enable debug mode
  vim.g.copilotchatassist_debug = true

  -- Log the request (protected against errors)
  pcall(function()
    if log and log.debug then
      log.debug({
        english = "Sending request to CopilotChat: " .. (string_utils and string_utils.truncate_string and string_utils.truncate_string(message, 100) or string.sub(message, 1, 100) .. "..."),
        spanish = "Enviando solicitud a CopilotChat: " .. (string_utils and string_utils.truncate_string and string_utils.truncate_string(message, 100) or string.sub(message, 1, 100) .. "...")
      })
    end
  end)

  -- Save complete prompt for debugging
  save_debug_info(message, "last_prompt")

  -- Wrap the original callback to process patches
  local original_callback = opts.callback
  opts.callback = function(response)
    -- Process patches in the response
    process_response(response)

    -- Save raw response for debugging
    if response then
      local content = type(response) == "string"
        and response
        or vim.inspect(response)

      save_debug_info(message, "response_raw", content)
    end

    -- Call the original callback if provided
    if original_callback then
      original_callback(response)
    end
  end

  -- Try to use CopilotChat API
  local ok, CopilotChat = pcall(require, "CopilotChat")

  if ok and CopilotChat and type(CopilotChat.ask) == "function" then
    log.debug({
      english = "Using CopilotChat API",
      spanish = "Usando API de CopilotChat"
    })

    local success, err = pcall(function()
      CopilotChat.ask(message, opts)
    end)

    if not success then
      log.error("Error calling CopilotChat.ask: " .. tostring(err))

      -- Fallback: Use command directly
      log.warn("Falling back to CopilotChat command")
      vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
    end
  else
    -- Fallback if API not available
    log.warn("CopilotChat API not available, using command")
    vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
  end
end

-- Open CopilotChat with specific context
function M.open(context, opts)
  opts = opts or {}
  if not opts.system_prompt then
    opts.system_prompt = require("copilotchatassist.prompts.system").default
  end

  local ok, CopilotChat = pcall(require, "CopilotChat")
  if ok and CopilotChat and type(CopilotChat.open) == "function" then
    local success = pcall(function()
      CopilotChat.open({ context = context }, opts)
    end)

    if not success then
      log.warn("Error opening CopilotChat with context, using command")
      vim.cmd("CopilotChat " .. vim.fn.shellescape(context))
    end
  else
    vim.cmd("CopilotChat " .. vim.fn.shellescape(context))
  end
end

-- Request TODO assistance
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
    callback = callback
  })
end

-- Get suggestions for next tasks based on current ones
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
    callback = callback
  })
end

-- Request explanation for a specific task
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
    headless = false,
    callback = callback
  })
end

-- Process content to extract patches
function M.process_for_patches(content)
  if not content or type(content) ~= "string" then
    log.debug("Invalid content for patch processing")
    return 0
  end

  local patches_module = require("copilotchatassist.patches")
  return patches_module.process_copilot_response(content)
end

-- Request implementation for a specific task
function M.implement_task(task, callback)
  local prompt = [[
Por favor, implementa la siguiente tarea usando código claro y bien estructurado:

- Título: ]] .. task.title .. [[
- Descripción: ]] .. (task.description or "N/A") .. [[
- Categoría: ]] .. (task.category or "N/A") .. [[

Si tu implementación requiere modificaciones en archivos existentes, proporciona los cambios en formato de patch:

```<lenguaje> path=/ruta/al/archivo start_line=<num> end_line=<num> mode=<modo>
<código>
```end

Donde <modo> puede ser:
- replace: Reemplazar las líneas start_line a end_line con el código proporcionado
- insert: Insertar el código en la posición start_line
- append: Añadir el código después de la línea end_line
- delete: Eliminar las líneas start_line a end_line

Si necesitas crear un archivo nuevo, usa path a la ruta completa donde debe crearse.
]]

  M.ask(prompt, {
    headless = false,
    callback = function(response)
      -- Process automatically for patches
      local patches_count = M.process_for_patches(response)

      if callback then
        callback(response, patches_count)
      end
    end
  })
end

-- Safe wrapper for CopilotChat.ask
function M.safe_ask(message, opts)
  opts = opts or {}

  local ok, result = pcall(function()
    M.ask(message, opts)
  end)

  if not ok then
    log.error("Failed to call CopilotChat: " .. tostring(result))
    return nil
  end

  return result
end

return M