-- Módulo de internacionalización (i18n) para CopilotChatAssist
-- Proporciona traducciones y funcionalidades relacionadas con el idioma

local M = {}
local options = require("copilotchatassist.options")
local log = require("copilotchatassist.utils.log")

-- Tabla con las traducciones disponibles
local translations = {
  -- Español
  spanish = {
    -- Menús y opciones generales
    menu = {
      what_action = "¿Qué acción deseas realizar?",
      update_all = "Actualizar todo",
      select_elements = "Seleccionar elementos",
      preview_changes = "Previsualizar cambios",
      advanced_options = "Opciones avanzadas",
      cancel = "Cancelar",
      back_to_main = "Volver al menú principal",
    },

    -- Opciones avanzadas de documentación
    advanced_options = {
      detect_git_changes = "Detectar elementos modificados en git",
      document_modified = "Documentar solo elementos modificados",
      document_undocumented = "Documentar solo elementos sin documentación",
      document_git_modified = "Documentar solo elementos modificados en git",
      preview_all_comments = "Previsualizar todos los comentarios",
      document_full_file = "Documentar todo el archivo",
      prompt_commits = "Número de commits a revisar (1-20): ",
    },

    -- Mensajes de documentación
    documentation = {
      no_elements_found = "No se encontraron elementos para documentar. Prueba con opciones avanzadas.",
      elements_found = "Se encontraron %d elementos para documentar",
      processing_elements = "Procesando %d elementos de documentación...",
      documentation_updated = "Documentación actualizada: %d/%d elementos procesados.",
      no_modified_elements = "No se detectaron cambios en los últimos %d commits",
      detected_changes = "Detectando cambios en git para los últimos %d commits...",
      found_modified_elements = "Se encontraron %d elementos modificados en los últimos %d commits",
      buffer_not_valid = "No se puede generar documentación: el buffer no es válido",
      unknown_filetype = "No se puede generar documentación: tipo de archivo desconocido",
      generation_failed = "No se pudo generar el contenido de documentación",
    },

    -- Panel de previsualización
    preview = {
      title = "PANEL DE PREVISUALIZACIÓN DE DOCUMENTACIÓN",
      instructions = "Usa la tecla <Space> para seleccionar/deseleccionar elementos",
      apply = "Presiona <Enter> para aplicar los elementos seleccionados",
      close = "Presiona <q> para cerrar el panel sin aplicar cambios",
      new_item = "[NUEVO]",
      update_item = "[ACTUALIZAR]",
      unchanged_item = "[SIN CAMBIOS]",
      no_selection = "No se seleccionó ningún elemento para aplicar",
      selected_items = "Procesando %d elementos seleccionados...",
      no_preview_items = "No hay elementos para previsualizar",
    },

    -- PRs y Git
    pr = {
      title_prefix = "Feature:",
      summary_section = "## Resumen",
      changes_section = "## Cambios realizados",
      test_section = "## Plan de pruebas",
      summary_bullet = "- Se ha implementado",
      test_todo = "- [ ] Verificar",
    },

    -- TODOs
    todo = {
      generate_title = "Generar TODOs para el proyecto",
      update = "Actualizar TODOs",
      add_new = "Añadir nuevo TODO",
      priority = "Prioridad",
      status = "Estado",
      pending = "Pendiente",
      in_progress = "En progreso",
      completed = "Completado",
      description = "Descripción",
    },
  },

  -- Inglés
  english = {
    -- Menus and general options
    menu = {
      what_action = "What action would you like to perform?",
      update_all = "Update all",
      select_elements = "Select elements",
      preview_changes = "Preview changes",
      advanced_options = "Advanced options",
      cancel = "Cancel",
      back_to_main = "Back to main menu",
    },

    -- Advanced documentation options
    advanced_options = {
      detect_git_changes = "Detect git modified elements",
      document_modified = "Document only modified elements",
      document_undocumented = "Document only undocumented elements",
      document_git_modified = "Document only git modified elements",
      preview_all_comments = "Preview all comments",
      document_full_file = "Document entire file",
      prompt_commits = "Number of commits to check (1-20): ",
    },

    -- Documentation messages
    documentation = {
      no_elements_found = "No elements found to document. Try advanced options.",
      elements_found = "Found %d elements to document",
      processing_elements = "Processing %d documentation elements...",
      documentation_updated = "Documentation updated: %d/%d elements processed.",
      no_modified_elements = "No changes detected in the last %d commits",
      detected_changes = "Detecting git changes for the last %d commits...",
      found_modified_elements = "Found %d modified elements in the last %d commits",
      buffer_not_valid = "Cannot generate documentation: buffer is not valid",
      unknown_filetype = "Cannot generate documentation: unknown file type",
      generation_failed = "Failed to generate documentation content",
    },

    -- Preview panel
    preview = {
      title = "DOCUMENTATION PREVIEW PANEL",
      instructions = "Use <Space> to select/deselect elements",
      apply = "Press <Enter> to apply selected elements",
      close = "Press <q> to close panel without applying changes",
      new_item = "[NEW]",
      update_item = "[UPDATE]",
      unchanged_item = "[UNCHANGED]",
      no_selection = "No elements were selected to apply",
      selected_items = "Processing %d selected elements...",
      no_preview_items = "No elements to preview",
    },

    -- PRs and Git
    pr = {
      title_prefix = "Feature:",
      summary_section = "## Summary",
      changes_section = "## Changes made",
      test_section = "## Test plan",
      summary_bullet = "- Implemented",
      test_todo = "- [ ] Verify",
    },

    -- TODOs
    todo = {
      generate_title = "Generate TODOs for the project",
      update = "Update TODOs",
      add_new = "Add new TODO",
      priority = "Priority",
      status = "Status",
      pending = "Pending",
      in_progress = "In progress",
      completed = "Completed",
      description = "Description",
    },
  }
}

-- Lenguajes soportados
M.supported_languages = {
  spanish = true,
  english = true,
}

-- Obtener el idioma actual configurado
-- @return string: El código del idioma actual
function M.get_current_language()
  -- Always prioritize the configured language from options
  local lang = options.get().language or "english"
  if not M.supported_languages[lang] then
    log.debug("Idioma no soportado: " .. lang .. ". Se usará inglés como predeterminado.")
    lang = "english"
  end
  return lang
end

-- Obtener el idioma para el código (puede ser distinto del idioma de la interfaz)
-- @return string: El código del idioma para el código
function M.get_code_language()
  local lang = options.get().code_language or "english"
  if not M.supported_languages[lang] then
    log.warn("Idioma de código no soportado: " .. lang .. ". Se usará inglés como predeterminado.")
    lang = "english"
  end
  return lang
end

-- Traducir una clave específica
-- @param key string: Clave de traducción en formato "categoria.subcategoria.clave"
-- @param args table: Argumentos para formatear la cadena (opcional)
-- @return string: Texto traducido
function M.t(key, args)
  -- Obtener el idioma actual
  local lang = M.get_current_language()

  -- Dividir la clave en partes
  local parts = {}
  for part in string.gmatch(key, "([^.]+)") do
    table.insert(parts, part)
  end

  -- Navegar por la tabla de traducciones
  local current = translations[lang]
  for i, part in ipairs(parts) do
    if not current[part] then
      log.warn("No se encontró la traducción para la clave: " .. key)
      return key  -- Si no se encuentra, devolver la clave como fallback
    end
    current = current[part]
  end

  -- Si el resultado no es una cadena, es un error
  if type(current) ~= "string" then
    log.warn("La clave de traducción no es una cadena: " .. key)
    return key
  end

  -- Si hay argumentos, formatear la cadena
  if args then
    return string.format(current, unpack(args))
  end

  return current
end

-- Traducir una clave para documentación de código
-- @param key string: Clave de traducción
-- @param args table: Argumentos para formatear la cadena (opcional)
-- @return string: Texto traducido para código
function M.code_t(key, args)
  -- Para la documentación de código, usamos el idioma de código configurado
  local orig_lang = options.get().language
  options.set({language = M.get_code_language()})

  local result = M.t(key, args)

  -- Restaurar el idioma original
  options.set({language = orig_lang})

  return result
end

-- Detectar el idioma de un texto
-- @param text string: Texto a analizar
-- @return string: Código del idioma detectado
function M.detect_language(text)
  if not text or text == "" then
    return M.get_current_language()
  end

  -- Una implementación básica que cuenta palabras específicas de cada idioma
  local spanish_words = {"de", "la", "el", "en", "para", "con", "por", "los", "las", "un", "una", "que", "es", "se"}
  local english_words = {"the", "of", "to", "in", "is", "are", "and", "for", "with", "this", "that", "from", "it"}

  local spanish_count = 0
  local english_count = 0

  -- Convertir texto a minúsculas para la comparación
  local lower_text = text:lower()

  -- Contar palabras en español
  for _, word in ipairs(spanish_words) do
    for _ in string.gmatch(lower_text, "%f[%a]" .. word .. "%f[%A]") do
      spanish_count = spanish_count + 1
    end
  end

  -- Contar palabras en inglés
  for _, word in ipairs(english_words) do
    for _ in string.gmatch(lower_text, "%f[%a]" .. word .. "%f[%A]") do
      english_count = english_count + 1
    end
  end

  -- Decidir el idioma basado en la mayor cantidad de palabras detectadas
  if spanish_count > english_count then
    return "spanish"
  else
    return "english"
  end
end

-- Traducir un texto de un idioma a otro
-- @param text string: Texto a traducir
-- @param target_lang string: Idioma de destino (opcional, por defecto el idioma actual)
-- @return string: Texto traducido si se procesa síncronamente, o una función para obtener el resultado si es async
function M.translate_text(text, target_lang, callback)
  if not text or text == "" then
    if callback then callback(text) end
    return text
  end

  target_lang = target_lang or M.get_current_language()
  local source_lang = M.detect_language(text)
  local log = require("copilotchatassist.utils.log")

  log.debug("Traduciendo texto de " .. source_lang .. " a " .. target_lang)

  -- Si el idioma origen es igual al destino, devolver el mismo texto
  if source_lang == target_lang then
    log.debug("Idioma origen igual al destino, devolviendo texto original")
    if callback then callback(text) end
    return text
  end

  -- Usar CopilotChat para traducir el texto
  local copilotchat_api = require("copilotchatassist.copilotchat_api")
  local result = text  -- Por defecto, devolver el mismo texto

  -- Si se proporciona un callback, es modo asíncrono
  if callback then
    log.debug("Modo asíncrono de traducción activado")
    local prompt = string.format(
      "Translate the following text from %s to %s. Return ONLY the translated text without explanations or formatting:\n\n%s",
      source_lang, target_lang, text
    )

    copilotchat_api.ask(prompt, {
      callback = function(response)
        -- Procesamiento de respuesta mejorado para manejar diferentes formatos
        log.debug("Procesando respuesta de traducción (tipo: " .. type(response) .. ")")

        local translated_text = nil

        -- Manejar diferentes tipos de respuesta
        if type(response) == "string" and response ~= "" then
          translated_text = response
        elseif type(response) == "table" then
          -- Si es una tabla, intentar extraer el campo 'content'
          if response.content and type(response.content) == "string" then
            log.debug("Extrayendo campo 'content' de la respuesta")
            translated_text = response.content
          end
        end

        -- Si tenemos un texto válido, procesarlo
        if translated_text and translated_text ~= "" then
          -- Limpiar posibles backticks o marcadores de código
          translated_text = translated_text:gsub("```%w*\n", ""):gsub("```", "")
          -- Eliminar espacios en blanco extra al principio y final
          translated_text = translated_text:gsub("^%s*(.-)%s*$", "%1")
          log.debug("Traducción completada: " .. #translated_text .. " caracteres")
          callback(translated_text)
        else
          log.error("Error en la traducción: respuesta vacía o inválida")
          callback(text)  -- Devolver texto original en caso de error
        end
      end,
      system_prompt = "You are a professional translator. Your task is to translate text accurately between languages while maintaining the original meaning and tone.",
    })

    -- En modo asíncrono, devolvemos el texto original y el callback manejará la traducción
    return text
  else
    -- En modo síncrono, usamos una implementación asíncrona con callbacks
    log.debug("Modo asíncrono de traducción activado (con callback)")

    -- Guardar el texto a traducir para debug
    local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
    vim.fn.mkdir(debug_dir, "p")
    local debug_file = debug_dir .. "/translate_request.txt"
    local f = io.open(debug_file, "w")
    if f then
      f:write("Source: " .. source_lang .. "\n")
      f:write("Target: " .. target_lang .. "\n")
      f:write("Text to translate:\n" .. text)
      f:close()
    end

    -- Crear una variable para almacenar el resultado y estado
    local result = {
      done = false,
      translated_text = text, -- Default al texto original
      start_time = os.time(),
      status_timer = nil,
      progress_timer = nil
    }

    -- Mostrar un spinner animado mientras se procesa
    local spinner_frames = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
    local spinner_idx = 1

    -- Iniciar animación de spinner
    result.status_timer = vim.loop.new_timer()
    result.status_timer:start(100, 100, function()
      vim.schedule(function()
        if not result.done then
          local frame = spinner_frames[spinner_idx]
          local elapsed = os.time() - result.start_time
          vim.cmd(string.format("echo '%s Traduciendo... (%ds)'", frame, elapsed))
          spinner_idx = (spinner_idx % #spinner_frames) + 1
        end
      end)
    end)

    -- Crear un prompt para la traducción
    local prompt = string.format(
      "Translate the following text from %s to %s. Return ONLY the translated text without explanations or formatting:\n\n%s",
      source_lang, target_lang, text
    )

    -- Log translation activity but don't show notification
    log.debug("Traduciendo texto...")

    -- Configurar un timeout por si la solicitud nunca retorna
    result.timeout_timer = vim.defer_fn(function()
      if not result.done then
        log.warn("Timeout alcanzado esperando traducción después de 60 segundos")
        result.done = true

        -- Limpiar timers
        if result.status_timer then
          result.status_timer:stop()
          result.status_timer:close()
        end

        vim.cmd("echo ''") -- Limpiar mensaje

        -- Log timeout, don't show notification
        log.warn("Timeout en la traducción. Se usará el texto original.")

        -- Devolver el texto original ya que falló la traducción
        if callback then
          callback(text)
        end
      end
    end, 60000) -- 60 segundos de timeout

    -- Enviar solicitud a CopilotChat
    copilotchat_api.ask(prompt, {
      callback = function(response)
        -- Marcar como completado inmediatamente
        result.done = true

        -- Detener y limpiar timers
        if result.status_timer then
          result.status_timer:stop()
          result.status_timer:close()
        end
        if result.timeout_timer then
          -- No hay un método .stop() para defer_fn, pero podemos simplemente
          -- ignorar la función ya que hemos marcado done = true
        end

        vim.cmd("echo ''") -- Limpiar mensaje de estado

        log.debug("Recibida respuesta de traducción (tipo: " .. type(response) .. ")")

        -- Procesar la respuesta según su tipo
        if type(response) == "string" and response ~= "" then
          result.translated_text = response
        elseif type(response) == "table" then
          if response.content and type(response.content) == "string" then
            log.debug("Extrayendo campo 'content' de la respuesta")
            result.translated_text = response.content
          else
            log.debug("Contenido de la tabla de respuesta: " .. vim.inspect(response))
          end
        end

        -- Procesar el texto si es válido
        if result.translated_text and result.translated_text ~= "" then
          -- Limpiar posibles backticks o marcadores de código
          result.translated_text = result.translated_text:gsub("```%w*\n", ""):gsub("```", "")
          -- Eliminar espacios en blanco extra al principio y final
          result.translated_text = result.translated_text:gsub("^%s*(.-)%s*$", "%1")
          log.debug("Traducción completada: " .. #result.translated_text .. " caracteres")

          -- Guardar la traducción para debug
          local translated_file = debug_dir .. "/translate_response.txt"
          local f = io.open(translated_file, "w")
          if f then
            f:write(result.translated_text)
            f:close()
          end

          -- Command completion - show at INFO level
          vim.notify("Translation complete.", vim.log.levels.INFO, { timeout = 2000 })

          -- Llamar al callback con el resultado
          if callback then
            callback(result.translated_text)
          end
        else
          log.error("Error en la traducción: respuesta vacía o inválida")

          -- Log error, don't show notification
          log.error("Error en la traducción. Se usará el texto original.")

          -- Llamar al callback con el texto original
          if callback then
            callback(text)
          end
        end
      end,
      system_prompt = "You are a professional translator. Your task is to translate text accurately between languages while maintaining the original meaning and tone.",
    })

    -- Para modo síncrono simulado, devolver el texto original
    -- El callback se ocupará de la respuesta real cuando llegue
    return text
  end
end

-- Actualizar descripciones/textos existentes al cambiar el idioma
-- @param text string: Texto a actualizar
-- @param target_lang string: Idioma de destino
-- @return string: Texto actualizado en el nuevo idioma
function M.update_language(text, target_lang)
  return M.translate_text(text, target_lang)
end

return M