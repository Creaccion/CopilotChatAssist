-- Módulo para documentar archivos completos usando CopilotChat
-- Este enfoque envía el archivo completo a CopilotChat para documentación
-- en lugar de intentar detectar y documentar elementos individuales

local M = {}
local log = require("copilotchatassist.utils.log")
local utils = require("copilotchatassist.utils")
local copilotchat = require("copilotchatassist.copilotchat_api")

-- Configuración de prompts por lenguaje
local language_prompts = {
  -- Java
  java = [[
  Por favor, añade documentación JavaDoc completa a este archivo Java siguiendo las mejores prácticas:
  - Documenta todas las clases, interfaces, records y métodos
  - Coloca JavaDoc antes de anotaciones (como @Service, @Component, etc.)
  - Documenta adecuadamente parámetros, valores de retorno y excepciones
  - Mantén el código exactamente igual, solo añade documentación
  - Sigue el estilo de Java 11+ para JavaDoc
  - NO añadas comentarios de implementación (como // implementation)
  - Incluye descripciones claras y concisas de la funcionalidad
  ]],

  -- Elixir
  elixir = [[
  Por favor, añade documentación completa a este archivo Elixir siguiendo las mejores prácticas:
  - Usa @moduledoc para documentar el módulo
  - Usa @doc para documentar funciones públicas
  - Usa @typedoc para documentar tipos si existen
  - Incluye secciones de ## Parameters y ## Returns solo si tienen contenido
  - No incluyas secciones vacías en la documentación
  - Mantén el código exactamente igual, solo añade documentación
  - La documentación debe seguir justo antes de la definición relacionada, sin líneas en blanco entre la documentación y el elemento documentado
  ]],

  -- JavaScript/TypeScript
  javascript = [[
  Por favor, añade documentación JSDoc completa a este archivo JavaScript siguiendo las mejores prácticas:
  - Documenta todas las funciones, clases y métodos
  - Usa etiquetas JSDoc apropiadas (@param, @returns, @throws, etc.)
  - Incluye tipos en la documentación cuando sea posible
  - Mantén el código exactamente igual, solo añade documentación
  - Incluye descripciones claras y concisas de la funcionalidad
  ]],

  typescript = [[
  Por favor, añade documentación TSDoc completa a este archivo TypeScript siguiendo las mejores prácticas:
  - Documenta todas las funciones, clases, interfaces y métodos
  - Usa etiquetas TSDoc apropiadas (@param, @returns, @throws, etc.)
  - Aprovecha los tipos de TypeScript en la documentación
  - Mantén el código exactamente igual, solo añade documentación
  - Incluye descripciones claras y concisas de la funcionalidad
  ]],

  -- Python
  python = [[
  Por favor, añade documentación docstring completa a este archivo Python siguiendo las mejores prácticas:
  - Usa docstrings para clases, métodos y funciones
  - Sigue el estilo de Google para docstrings (con secciones Args:, Returns:, Raises:)
  - Mantén el código exactamente igual, solo añade documentación
  - Incluye descripciones claras y concisas de la funcionalidad
  - Documenta tipos de parámetros y retorno
  ]],

  -- Go
  go = [[
  Por favor, añade documentación completa a este archivo Go siguiendo las mejores prácticas:
  - Documenta todas las funciones, tipos y métodos exportados
  - Los comentarios deben comenzar con el nombre del elemento
  - Mantén el código exactamente igual, solo añade documentación
  - Incluye descripciones claras y concisas de la funcionalidad
  - Sigue la convención de documentación de la biblioteca estándar de Go
  ]],

  -- Lua
  lua = [[
  Por favor, añade documentación completa a este archivo Lua siguiendo las mejores prácticas:
  - Usa comentarios con -- para documentación
  - Sigue el estilo de LDoc/EmmyLua para parámetros (@param) y retorno (@return)
  - Mantén el código exactamente igual, solo añade documentación
  - Incluye descripciones claras y concisas de la funcionalidad
  ]],

  -- Rust
  rust = [[
  Por favor, añade documentación completa a este archivo Rust siguiendo las mejores prácticas:
  - Usa comentarios /// para documentación de API pública
  - Usa comentarios //! para documentación a nivel de módulo
  - Documenta todas las funciones, estructuras, traits y métodos públicos
  - Incluye ejemplos donde sea apropiado con ```rust ... ```
  - Mantén el código exactamente igual, solo añade documentación
  - Incluye descripciones claras y concisas de la funcionalidad
  ]],

  -- Default (para lenguajes sin prompt específico)
  default = [[
  Por favor, añade documentación completa a este archivo siguiendo las mejores prácticas para este lenguaje:
  - Documenta todas las funciones, clases, métodos y otros elementos importantes
  - Sigue las convenciones estándar del lenguaje para la documentación
  - Mantén el código exactamente igual, solo añade documentación
  - Incluye descripciones claras y concisas de la funcionalidad
  ]]
}

-- Obtiene el prompt adecuado para un lenguaje
-- @param filetype string: Tipo de archivo/lenguaje
-- @return string: Prompt para ese lenguaje
function M.get_language_prompt(filetype)
  -- Mapear algunos filetypes a sus equivalentes
  local filetype_map = {
    ["ts"] = "typescript",
    ["js"] = "javascript",
    ["jsx"] = "javascript",
    ["tsx"] = "typescript",
    ["py"] = "python",
    ["ex"] = "elixir",
    ["exs"] = "elixir",
  }

  -- Usar el mapping si existe
  if filetype_map[filetype] then
    filetype = filetype_map[filetype]
  end

  return language_prompts[filetype] or language_prompts.default
end

-- Documentar un archivo completo usando CopilotChat
-- @param buffer número: ID del buffer a documentar
-- @param opts tabla: Opciones adicionales (opcional)
-- @return boolean, string?: true y código documentado si tiene éxito, false y mensaje de error en caso contrario
function M.document_buffer(buffer, opts)
  opts = opts or {}
  local filetype = vim.bo[buffer].filetype

  if not filetype or filetype == "" then
    return false, "No se pudo determinar el tipo de archivo"
  end

  log.info("Iniciando documentación completa para buffer " .. buffer .. " con tipo " .. filetype)

  -- Obtener la ruta del archivo si está disponible
  local file_path = vim.api.nvim_buf_get_name(buffer)

  -- Verificación adicional para asegurarse de que la ruta es correcta
  if not file_path or file_path == "" then
    log.error("No se pudo determinar la ruta del archivo para el buffer: " .. buffer)
    return false, "No se pudo determinar la ruta del archivo"
  end

  -- Depuración para verificar la ruta del archivo
  local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
  vim.fn.mkdir(debug_dir, "p")
  local path_debug_file = debug_dir .. "/buffer_path_debug.txt"
  local path_debug_f = io.open(path_debug_file, "w")
  if path_debug_f then
    path_debug_f:write("Buffer ID: " .. buffer .. "\n")
    path_debug_f:write("Ruta determinada: " .. file_path .. "\n")
    path_debug_f:write("Es un archivo real: " .. tostring(file_path and file_path ~= "") .. "\n")
    path_debug_f:write("Nombre del archivo: " .. vim.fn.fnamemodify(file_path, ":t") .. "\n")
    path_debug_f:close()
  end

  local is_real_file = file_path and file_path ~= ""
  local original_modified = vim.bo[buffer].modified

  -- Verificar si el archivo existe y tiene permisos de escritura
  local file_writable = is_real_file and vim.fn.filewritable(file_path) == 1

  -- Guardar una copia del buffer original para casos de error
  local original_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  if not original_lines or #original_lines == 0 then
    return false, "Buffer vacío"
  end

  local content = table.concat(original_lines, "\n")

  -- Obtener el prompt específico para este lenguaje
  local language_prompt = M.get_language_prompt(filetype)

  -- Construir el prompt completo
  local prompt = language_prompt .. "\n\n```" .. filetype .. "\n" .. content .. "\n```\n\nDevuelve solo el código " .. filetype .. " completo con la documentación añadida."

  log.debug("Enviando archivo a CopilotChat para documentación...")

  -- Mostrar notificación de inicio
  vim.notify("Documentando archivo completo con CopilotChat...", vim.log.levels.INFO)

  -- Preparar para almacenar las líneas documentadas
  local documented_lines = {}

  -- Configurar un callback para procesar la respuesta de CopilotChat
  local callback_executed = false
  local callback_result = nil

  local function process_response(response)
    callback_executed = true
    callback_result = response

    -- Guardar la respuesta completa para depuración (antes de cualquier procesamiento)
    local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    vim.fn.mkdir(debug_dir, "p")
    local raw_debug_file = debug_dir .. "/response_raw.txt"
    local raw_file = io.open(raw_debug_file, "w")
    if raw_file then
      if type(response) == "string" then
        raw_file:write(response)
      else
        raw_file:write(vim.inspect(response))
      end
      raw_file:close()
      log.debug("Respuesta raw guardada en " .. raw_debug_file)
    end

    log.debug("Respuesta recibida de CopilotChat: " .. (type(response) == "string" and #response or "no es string") .. " caracteres")

    -- Verificar que la respuesta no está vacía
    if not response then
      log.error("La respuesta de CopilotChat está vacía")
      vim.notify("La respuesta de CopilotChat está vacía. Intente nuevamente.", vim.log.levels.ERROR)
      return
    end

    -- Manejar diferentes tipos de respuestas
    local documented_code

    if type(response) == "table" then
      log.debug("La respuesta es una tabla Lua")

      -- Si es una tabla con un campo 'content', usar ese campo
      if response.content then
        log.debug("La tabla contiene un campo 'content'")
        documented_code = response.content
      else
        -- Convertir la tabla a string si no tiene campo 'content'
        log.debug("La tabla no contiene un campo 'content', usando toda la tabla")
        documented_code = vim.inspect(response)
      end
    elseif type(response) == "string" then
      documented_code = response
    else
      -- Convertir cualquier otro tipo a string
      log.debug("La respuesta es de tipo: " .. type(response))
      documented_code = tostring(response)
    end

    -- Guardar la respuesta procesada para depuración
    local debug_file = debug_dir .. "/last_response.txt"
    local file = io.open(debug_file, "w")
    if file then
      if type(documented_code) == "string" then
        file:write(documented_code)
      else
        file:write(vim.inspect(documented_code))
      end
      file:close()
      log.debug("Respuesta procesada guardada en " .. debug_file)
    end

    -- Verificar que tenemos contenido para procesar
    if not documented_code or (type(documented_code) == "string" and documented_code == "") then
      log.error("No se pudo extraer contenido documentado de la respuesta")
      vim.notify("No se pudo extraer contenido documentado de la respuesta", vim.log.levels.ERROR)
      return
    end

    -- Si el contenido es una cadena, intentar procesar cualquier formato especial
    if type(documented_code) == "string" then
      -- Detectar si la respuesta es JSON
      local is_json = documented_code:match("^%s*{") ~= nil

      if is_json then
        log.debug("Detectado formato JSON en la respuesta")
        -- Intentar extraer el campo 'content' del JSON
        local content_match = documented_code:match('"content":%s*"(.-)"') or documented_code:match("content%s*=%s*\"(.-)\"")

        if not content_match then
          -- Intento alternativo para estructuras de tabla Lua
          content_match = documented_code:match("content%s*=%s*\"([^\"]+)\"")
        end

        if content_match then
          log.debug("Extraído campo 'content' del JSON")
          documented_code = content_match
        else
          log.warn("No se pudo extraer el campo 'content' del JSON, intentando con toda la respuesta")
        end
      end
    end

    -- Extraer el código de la respuesta usando la función mejorada
    documented_code = utils.extract_code_block(documented_code)

    -- Verificar que se ha extraído correctamente el código
    if not documented_code or documented_code == "" then
      log.error("No se pudo extraer código documentado de la respuesta")
      vim.notify("No se pudo extraer código documentado de la respuesta", vim.log.levels.ERROR)
      return
    end

    -- Limpiar y llenar el array de líneas documentadas
    while #documented_lines > 0 do
      table.remove(documented_lines)
    end

    for line in documented_code:gmatch("([^\n]*)\n?") do
      table.insert(documented_lines, line)
    end

    -- Verificar que tenemos contenido válido
    if #documented_lines == 0 then
      log.error("No se obtuvo contenido válido de CopilotChat")
      vim.notify("No se obtuvo contenido válido de CopilotChat", vim.log.levels.ERROR)
      return
    end

    -- Preparamos todo para mostrar el resultado
    local buf_utils = require("copilotchatassist.utils.buffer")

    -- Siempre abrimos un buffer de previsualización para ver los cambios
    local preview_buf = buf_utils.open_split_buffer("[CopilotChat] Documentación generada", documented_code)
    vim.notify("Previsualizando documentación generada", vim.log.levels.INFO)

    -- Si estamos en modo sólo previsualización, terminamos aquí
    if opts.preview_only then
      log.info("Modo sólo previsualización, no se actualizará el buffer original")
      vim.notify("Modo sólo previsualización. Use :w para guardar los cambios manualmente si lo desea.", vim.log.levels.INFO)
      return
    end

    -- Actualizar el buffer original si sigue siendo válido
    if pcall(function() return vim.api.nvim_buf_is_valid(buffer) end) and vim.api.nvim_buf_is_valid(buffer) then
      -- Usar pcall para todas las operaciones de buffer para evitar errores
      local success = pcall(function()
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, documented_lines)
        vim.bo[buffer].modified = true
      end)

      if success then
        log.info("Documentación aplicada al buffer " .. buffer)
        vim.notify("Documentación aplicada al buffer", vim.log.levels.INFO)
      else
        log.error("Error al aplicar documentación al buffer original " .. buffer)
        vim.notify("No se pudo actualizar el buffer original, pero puede copiar desde la previsualización", vim.log.levels.WARN)
        return
      end
    else
      log.error("El buffer " .. buffer .. " no es válido")
      vim.notify("El buffer original no es válido, no se pueden aplicar los cambios", vim.log.levels.ERROR)
      return
    end

    -- Guardar el archivo si:
    -- 1. El usuario ha solicitado guardar explícitamente (opts.save)
    -- 2. No ha solicitado explícitamente NO guardar (not opts.no_save)
    -- 3. El archivo existe y tiene permisos de escritura

    -- Verificar nuevamente la ruta del archivo actual
    local current_path = vim.api.nvim_buf_get_name(buffer)
    if current_path and current_path ~= "" and current_path ~= file_path then
      log.warn("La ruta del archivo ha cambiado durante el proceso: " .. file_path .. " -> " .. current_path)
      file_path = current_path
    end

    -- Verificar si el archivo es escribible
    local is_now_writable = vim.fn.filewritable(file_path) == 1

    if (opts.save or not opts.no_save) and file_path and file_path ~= "" then
      -- Añadir mensaje para depuración
      log.info("Intentando guardar archivo en: " .. file_path)
      log.info("Archivo escribible: " .. tostring(is_now_writable))

      if not is_now_writable then
        log.warn("El archivo no tiene permisos de escritura, pero intentaremos guardar de todos modos")
        vim.notify("Advertencia: El archivo no tiene permisos de escritura, se intentará guardar de todos modos", vim.log.levels.WARN)
      end
      local file_utils = require("copilotchatassist.utils.file")

      -- Verificar nuevamente la ruta del archivo para asegurar que sea la correcta
      local current_buf_path = vim.api.nvim_buf_get_name(buffer)
      if current_buf_path and current_buf_path ~= "" and vim.fn.filereadable(current_buf_path) == 1 then
        file_path = current_buf_path  -- Usar la ruta actualizada del buffer actual
      end

      -- Guardar información de diagnóstico antes de escribir
      local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
      vim.fn.mkdir(debug_dir, "p")
      local debug_file = debug_dir .. "/pre_write_debug.txt"
      local debug_f = io.open(debug_file, "w")
      if debug_f then
        debug_f:write("file_path: " .. file_path .. "\n")
        debug_f:write("buffer: " .. buffer .. "\n")
        debug_f:write("current_buf_path: " .. (current_buf_path or "nil") .. "\n")
        debug_f:write("documented_code type: " .. type(documented_code) .. "\n")
        debug_f:write("documented_code length: " .. #documented_code .. " bytes\n")
        debug_f:write("documented_code (first 500 chars): \n" .. documented_code:sub(1, 500) .. "...\n")
        debug_f:write("file writable: " .. tostring(vim.fn.filewritable(file_path)) .. "\n")
        debug_f:close()
      end

      -- Intentar escribir el archivo con modo forzado
      -- Imprimir información adicional para depuración
      log.debug("Intentando escribir en archivo: " .. file_path)
      log.debug("Verificando permisos de escritura: " .. tostring(vim.fn.filewritable(file_path)))

      -- Asegurarse de que el contenido es el código documentado
      if type(documented_code) == "string" and documented_code:match("```") then
        documented_code = utils.extract_code_block(documented_code)
      end

      local saved = file_utils.write_file(file_path, documented_code, true) -- true para usar modo forzado

      -- Más diagnóstico después del intento
      local post_debug_file = debug_dir .. "/post_write_debug.txt"
      local post_debug_f = io.open(post_debug_file, "w")
      if post_debug_f then
        post_debug_f:write("Save result: " .. tostring(saved) .. "\n")
        post_debug_f:write("File path used: " .. file_path .. "\n")
        post_debug_f:write("Buffer: " .. buffer .. "\n")

        -- Verificar si el archivo existe y si contiene lo esperado
        local file_exists = vim.fn.filereadable(file_path) == 1
        post_debug_f:write("File exists after save: " .. tostring(file_exists) .. "\n")

        if file_exists then
          local content_after = file_utils.read_file(file_path)
          post_debug_f:write("Content length after save: " .. (content_after and #content_after or "nil") .. " bytes\n")
          local content_matches = content_after and content_after == documented_code
          post_debug_f:write("Content matches: " .. tostring(content_matches) .. "\n")

          -- Si el contenido no coincide, intentar usar comando del sistema directamente
          if not content_matches and saved then
            post_debug_f:write("Trying alternative write method...\n")
            local tmp_file = os.tmpname()
            local tmp = io.open(tmp_file, "w")
            if tmp then
              tmp:write(documented_code)
              tmp:close()
              local cmd = string.format("cat %s > %s", vim.fn.shellescape(tmp_file), vim.fn.shellescape(file_path))
              local result = os.execute(cmd)
              post_debug_f:write("Alternative write result: " .. tostring(result) .. "\n")
              os.remove(tmp_file)

              -- Verificar nuevamente
              content_after = file_utils.read_file(file_path)
              post_debug_f:write("Content length after alternative save: " .. (content_after and #content_after or "nil") .. " bytes\n")
              post_debug_f:write("Content matches after alternative: " .. tostring(content_after == documented_code) .. "\n")
            end
          end
        end
        post_debug_f:close()
      end

      if saved then
        -- Recargar el buffer para reflejar los cambios guardados
        -- Usar pcall para evitar errores si el buffer ya no está disponible
        local reload_success = pcall(function()
          if vim.api.nvim_buf_is_valid(buffer) then
            -- Si estamos en el buffer que estamos actualizando
            if vim.api.nvim_get_current_buf() == buffer then
              vim.cmd("e!")
            end
          end
        end)

        vim.notify("Documentación aplicada y guardada en " .. file_path, vim.log.levels.INFO)
      else
        log.error("Error al guardar el archivo: " .. file_path)
        vim.notify("No se pudo guardar el archivo, pero el buffer ha sido actualizado. Ver logs para más detalles.", vim.log.levels.WARN)
      end
    else
      if opts.no_save then
        log.info("Modo sin guardado automático")
        vim.notify("Buffer actualizado (sin guardado automático)", vim.log.levels.INFO)
      elseif not (file_path and file_path ~= "") then
        log.info("El buffer no tiene archivo asociado")
        vim.notify("Buffer actualizado (sin archivo asociado)", vim.log.levels.INFO)
      elseif vim.fn.filewritable(file_path) ~= 1 then
        log.warn("El archivo no tiene permisos de escritura: " .. file_path)
        vim.notify("Buffer actualizado (archivo sin permisos de escritura)", vim.log.levels.WARN)
      end
    end
  end

  -- Enviar a CopilotChat con callback
  local ok = pcall(function()
    copilotchat.ask(prompt, {
      callback = process_response
    })
  end)

  if not ok then
    log.error("Error al enviar la solicitud a CopilotChat")
    return false, "Error al comunicarse con CopilotChat"
  end

  -- Informar al usuario que la solicitud ha sido enviada
  log.info("Solicitud enviada a CopilotChat correctamente, esperando respuesta...")
  return true, "Solicitud de documentación enviada a CopilotChat, procesando..."
end

-- Documentar un archivo desde su ruta
-- @param file_path string: Ruta del archivo a documentar
-- @param opts tabla: Opciones adicionales (opcional)
-- @return boolean, string?: true y código documentado si tiene éxito, false y mensaje de error en caso contrario
function M.document_file(file_path, opts)
  opts = opts or {}

  -- Si el archivo no existe, devolver error
  if vim.fn.filereadable(file_path) == 0 then
    log.error("El archivo no existe o no es legible: " .. file_path)
    return false, "El archivo no existe o no es legible: " .. file_path
  end

  -- Determinar si el archivo tiene permisos de escritura
  local is_writable = vim.fn.filewritable(file_path) == 1

  -- Leer el contenido del archivo directamente usando utilidades de archivo
  local file_utils = require("copilotchatassist.utils.file")
  local content = file_utils.read_file(file_path)

  if not content or content == "" then
    return false, "No se pudo leer el contenido del archivo o está vacío: " .. file_path
  end

  -- Determinar el tipo de archivo basado en su extensión
  local filetype = vim.fn.fnamemodify(file_path, ":e")

  -- Obtener el prompt específico para este lenguaje
  local language_prompt = M.get_language_prompt(filetype)

  -- Construir el prompt completo
  local prompt = language_prompt .. "\n\n```" .. filetype .. "\n" .. content .. "\n```\n\nDevuelve solo el código " .. filetype .. " completo con la documentación añadida."

  log.debug("Enviando archivo " .. file_path .. " a CopilotChat para documentación...")

  -- Mostrar notificación de inicio
  vim.notify("Documentando archivo " .. file_path .. " con CopilotChat...", vim.log.levels.INFO)

  -- Enviar a CopilotChat
  local ok, response = pcall(function()
    return copilotchat.ask(prompt)
  end)

  if not ok or not response then
    log.error("Error al obtener respuesta de CopilotChat: " .. (response or "respuesta vacía"))
    return false, "Error al comunicarse con CopilotChat: " .. (response or "respuesta vacía")
  end

  log.debug("Respuesta recibida de CopilotChat, procesando...")

  -- Extraer el código de la respuesta
  local documented_code = utils.extract_code_block(response)

  if not documented_code or documented_code == "" then
    log.error("No se pudo extraer código documentado de la respuesta")
    return false, "No se pudo extraer código documentado de la respuesta"
  end

  -- Si el usuario quiere previsualizar el resultado
  if opts.preview then
    -- Abrir un buffer de previsualización
    local buf_utils = require("copilotchatassist.utils.buffer")
    buf_utils.open_split_buffer("[CopilotChat] " .. vim.fn.fnamemodify(file_path, ":t") .. " (documentado)", documented_code)
    vim.notify("Previsualizando documentación para " .. file_path, vim.log.levels.INFO)
    return true, documented_code
  end

  -- Si no se solicita guardar explícitamente y no hay un buffer abierto para este archivo
  -- abrir un buffer temporal con el contenido documentado
  local buffer = vim.fn.bufnr(file_path)
  if buffer == -1 or not opts.save then
    -- Abrir un buffer con el contenido documentado
    local buf_utils = require("copilotchatassist.utils.buffer")
    buf_utils.open_split_buffer("[CopilotChat] " .. vim.fn.fnamemodify(file_path, ":t") .. " (documentado)", documented_code)
    vim.notify("Documentación generada. Use :w para guardar los cambios.", vim.log.levels.INFO)
    return true, documented_code
  end

  -- Si se solicita guardar y el archivo tiene permisos de escritura
  if opts.save and is_writable then
    local success = file_utils.write_file(file_path, documented_code)
    if success then
      -- Si hay un buffer abierto para este archivo, recargarlo
      if buffer ~= -1 then
        -- Asegurarse de que el buffer esté cargado
        if not vim.api.nvim_buf_is_loaded(buffer) then
          vim.fn.bufload(buffer)
        end

        -- Recargar el buffer
        local current_buf = vim.api.nvim_get_current_buf()
        if current_buf == buffer then
          vim.cmd("e!")
        else
          -- Actualizar el buffer sin cambiar el buffer actual
          vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(documented_code, "\n"))
        end
      end

      vim.notify("Documentación añadida y guardada en " .. file_path, vim.log.levels.INFO)
    else
      vim.notify("No se pudo guardar el archivo documentado: " .. file_path, vim.log.levels.ERROR)
      return false, "Error al guardar el archivo documentado: " .. file_path
    end
  end

  return true, documented_code
end

return M