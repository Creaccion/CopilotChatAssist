-- Simplified wrapper for CopilotChat API integration
-- This version delegates more functionality to CopilotChat and eliminates duplicated code

local options = require("copilotchatassist.options")
local log = require("copilotchatassist.utils.log")
local string_utils = require("copilotchatassist.utils.string")
local response_validator = require("copilotchatassist.utils.response_validator")

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

  -- Establecer la opción headless por defecto en true para ocultar la ventana
  if opts.headless == nil then
    opts.headless = true
  end

  if not opts.system_prompt then
    opts.system_prompt = options.get().system_prompt or
      require("copilotchatassist.prompts.system").default
  end

  -- Guardar el contexto para futura referencia
  -- Esto permite que CopilotChat acceda al contexto más reciente
  if message and #message > 20 and (message:match("^%-%-[%s]*[%w%s]+[%s]*%-%-") or
                                   message:match("Project[%s]*[Cc]ontext") or
                                   message:match("Ticket[%s]*[Ss]ynthesis") or
                                   message:match("[Rr]equirement[%s]*[Cc]ontext")) then
    -- Parece ser un contexto de proyecto/ticket - guardarlo globalmente
    vim.g.copilotchatassist_context = message
    log.debug("Guardando mensaje como contexto global para CopilotChat (" .. #message .. " bytes)")
  end

  -- Configurar un timeout para evitar bloqueos indefinidos
  local timeout_ms = opts.timeout or 120000 -- 2 minutos por defecto
  local timer = nil

  -- Si hay un callback, crear un timer de timeout
  if opts.callback and type(opts.callback) == "function" then
    timer = vim.loop.new_timer()
    timer:start(timeout_ms, 0, vim.schedule_wrap(function()
      log.error("Timeout alcanzado al esperar respuesta de CopilotChat. La operación tomó más de " .. (timeout_ms/1000) .. " segundos.")

      -- Si hay un callback original, envolvemos para pasar un mensaje de error
      if opts.callback then
        opts.callback(nil)
      end

      -- Limpiar timer
      if timer then
        timer:stop()
        timer:close()
      end
    end))
  end

  -- Respetar la configuración de nivel de log
  -- No forzar modo debug para respetar log_level
  vim.g.copilotchatassist_silent = true

  -- Log the request (protected against errors)
  pcall(function()
    -- No mostrar mensajes de debug sobre envío de solicitud a CopilotChat
  end)

  -- Guardar el prompt completo para depuración
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")
  local debug_file = debug_dir .. "/last_prompt.txt"
  local file = io.open(debug_file, "w")
  if file then
    file:write(message)
    file:close()
    -- No mostrar mensaje de debug sobre guardar prompt
  end

  -- Wrap the original callback to process patches and validate responses
  local original_callback = opts.callback
  if opts.callback and type(opts.callback) == "function" then
    -- Registrar la operación con el gestor de estado (si está disponible)
    local operation_id = nil
    local operation = nil
    local state_manager = nil

    pcall(function()
      state_manager = require("copilotchatassist.utils.state_manager")
      operation = state_manager.start_operation("copilot_api_call")
      operation_id = operation.id
      log.debug("Operación registrada con ID: " .. operation_id)
    end)

    opts.callback = function(response)
      -- Cancelar el timer de timeout si existe
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end

      -- Verificar si la operación sigue siendo válida
      local is_operation_valid = true
      if operation and state_manager then
        is_operation_valid = operation:is_current()
        if not is_operation_valid then
          log.warn("Operación " .. operation_id .. " ya no es la actual, respuesta ignorada")
          return
        end
      end

      -- Proteger contra respuestas malformadas o inexistentes
      if response == nil then
        log.error("No se recibió respuesta de CopilotChat (timeout o error interno)")
        if original_callback then
          original_callback(nil)  -- Pasar nil para indicar error
        else
          log.error("Error crítico: callback es nil en el momento de procesar la respuesta")
        end

        -- Completar operación si está disponible el gestor de estado
        if operation then
          operation:complete()
        end

        return
      end

      -- Registrar información sobre la respuesta recibida
      log.debug("Tipo de respuesta recibida de CopilotChat: " .. type(response))

      -- Si es una tabla, intentar ver su estructura
      if type(response) == "table" then
        local table_info = ""
        pcall(function()
          table_info = vim.inspect(response):sub(1, 100) .. "..."
        end)
        log.debug("Estructura de la respuesta (parcial): " .. table_info)

        -- Guardar la respuesta para diagnóstico
        local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
        vim.fn.mkdir(debug_dir, "p")
        local debug_file = debug_dir .. "/api_response.txt"
        local file = io.open(debug_file, "w")
        if file then
          file:write(vim.inspect(response))
          file:close()
          log.debug("Respuesta guardada en: " .. debug_file)
        end
      end

      -- Validar la respuesta antes de ejecutar el callback original
      -- Esto evita problemas con respuestas malformadas o vacías
      local validated_response = nil

      if response ~= nil then
        -- Intentar validar y procesar la respuesta
        log.debug("Validando respuesta de CopilotChat")
        validated_response = response_validator.process_response(response, 10) -- Mínimo 10 caracteres

        -- Guardar información de diagnóstico
        local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
        vim.fn.mkdir(debug_dir, "p")
        local debug_file = debug_dir .. "/callback_response_validation.txt"
        local file = io.open(debug_file, "w")
        if file then
          file:write("Tipo de respuesta: " .. type(response) .. "\n")
          file:write("Respuesta validada: " .. (validated_response and "OK (" .. #validated_response .. " caracteres)" or "NULL") .. "\n")
          file:write("Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
          file:close()
          log.debug("Resultados de validación guardados en: " .. debug_file)
        end
      else
        log.error("Respuesta nil recibida de CopilotChat")
      end

      -- Ejecutar callback original solo si la respuesta es válida
      if validated_response then
        -- Flag para evitar múltiples callbacks
        local callback_executed = false

        local status, error_msg = pcall(function()
          if not callback_executed then
            callback_executed = true
            log.debug("Ejecutando callback con respuesta validada, longitud: " .. #validated_response)
            original_callback(validated_response)
          else
            log.debug("Callback ya ejecutado previamente, ignorando llamada adicional")
          end
        end)

        if not status then
          log.error("Error en callback de CopilotChat: " .. tostring(error_msg))
          -- NO intentamos llamar de nuevo con nil para evitar ciclos
        end
      else
        log.error("No se pudo obtener una respuesta válida de CopilotChat, no se ejecutará el callback")
      end
    end
  end

  -- Try to use CopilotChat API
  local ok, CopilotChat = pcall(require, "CopilotChat")

  if ok and CopilotChat then
    -- No mostrar mensajes de debug sobre CopilotChat cargado

    -- Verificar que CopilotChat.ask sea una función
    if type(CopilotChat.ask) == "function" then
      -- No mostrar mensajes de debug sobre CopilotChat.ask

      local success, err = pcall(function()
        -- No mostrar mensajes de debug sobre intentar llamar a CopilotChat.ask

        -- IMPORTANTE: No envolver el callback nuevamente, ya está envuelto en las líneas 101-130
        -- Esto evita dobles llamadas y problemas con respuestas nulas
        -- Solo registrar evento de diagnóstico
        log.debug("Enviando solicitud a CopilotChat con callback único")

        CopilotChat.ask(message, opts)
      end)

      if not success then
        log.error("Error al llamar a CopilotChat.ask: " .. tostring(err))
        -- Solo registrar en log
        -- Plan B: Usar el comando directamente
        vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
      end
    else
      log.error("CopilotChat.ask no es una función: " .. type(CopilotChat.ask))
      -- Solo registrar en log
      -- Plan B: Usar el comando directamente
      vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
    end
  else
    log.error("No se pudo cargar CopilotChat: " .. tostring(CopilotChat))
    -- Solo registrar en log
    vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
  end
end

-- Open CopilotChat with specific context
function M.open(context, opts)
  opts = opts or {}
  if not opts.system_prompt then
    opts.system_prompt = require("copilotchatassist.prompts.system").default
  end

  -- Establecer la opción headless por defecto en true para ocultar la ventana
  if opts.headless == nil then
    opts.headless = true
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
      -- Solo registrar en log
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
    -- No mostrar mensaje de debug sobre contenido inválido
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