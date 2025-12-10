-- Este es un archivo temporal que contiene las mejoras para el sistema de idioma en TODOs
-- Aquí hay dos fragmentos de código que debes aplicar:

-- 1. En /lua/copilotchatassist/prompts/todo_requests.lua, reemplaza la línea que define prompt_start con:

local prompt_start = string.format([[Siempre usando el lenguaje %s para nuestra interaccion y lo relacionado a los TODOS, sin traducir codigo o elementos del código
, y el lenguaje %s para todo lo relacionado al código, documentacion, debugs.

IMPORTANTE: Todas las tareas, categorías, títulos y descripciones en la tabla deben generarse en %s. No solo el formato de la tabla sino también su contenido debe estar completamente en %s.

Asegúrate de que las categorías como 'testing', 'feature', 'refactor', 'docs', etc. y todos los valores de la tabla estén en el idioma %s.]], user_language, code_language, user_language, user_language, user_language)

-- 2. En /lua/copilotchatassist/todos/init.lua, busca la sección que detecta y traduce el idioma
-- y reemplázala con este código mejorado:

-- Verificar si necesitamos traducir el contenido
local user_language = options.get().language
local current_language = nil

-- Detectar idioma actual del contenido con más patrones
if content and (content:match("integración") or content:match("validación") or
   content:match("documentación") or content:match("PENDIENTE") or content:match("Total Tareas") or
   content:match("pendientes") or content:match("listas") or content:match("%% avance") or
   content:match("refactor") or content:match("implementar") or content:match("revisar")) then
  current_language = "spanish"
  log.debug({
    english = "Detected Spanish content in the response",
    spanish = "Se detectó contenido en español en la respuesta"
  })
else
  current_language = "english"
  log.debug({
    english = "Detected English content or no specific pattern matched",
    spanish = "Se detectó contenido en inglés o ningún patrón específico coincidió"
  })
end

-- Si el idioma actual no coincide con el configurado, realizar traducción
if current_language ~= user_language and content then
  if user_language == "english" and current_language == "spanish" then
    log.debug({
      english = "Content language doesn't match configured language. Translating from Spanish to English",
      spanish = "El idioma del contenido no coincide con el idioma configurado. Traduciendo de español a inglés"
    })

    -- Realizar traducciones específicas para categorías y estados (español -> inglés)
    -- Categorías
    content = content:gsub("integración", "integration")
    content = content:gsub("validación", "validation")
    content = content:gsub("documentación", "documentation")
    content = content:gsub("interfaz", "interface")
    content = content:gsub("testing", "testing")
    content = content:gsub("formato", "format")
    content = content:gsub("refactor", "refactor")
    content = content:gsub("feature", "feature")
    content = content:gsub("implementación", "implementation")
    content = content:gsub("diseño", "design")
    content = content:gsub("seguridad", "security")
    content = content:gsub("rendimiento", "performance")
    content = content:gsub("bugs", "bugs")
    content = content:gsub("investigación", "research")
    content = content:gsub("docs", "docs")

    -- Estados
    content = content:gsub("TODO", "TODO")
    content = content:gsub("PENDIENTE", "TODO")
    content = content:gsub("EN PROGRESO", "IN PROGRESS")
    content = content:gsub("COMPLETADO", "DONE")

    -- Resumen
    content = content:gsub("Total Tareas:", "Total Tasks:")
    content = content:gsub("Total pendientes:", "Total pending:")
    content = content:gsub("Total listas:", "Total completed:")
    content = content:gsub("%% avance:", "%% progress:")

    -- Palabras comunes en descripciones
    content = content:gsub("Implementar", "Implement")
    content = content:gsub("Revisar", "Review")
    content = content:gsub("Actualizar", "Update")
    content = content:gsub("Mejorar", "Improve")
    content = content:gsub("Validar", "Validate")
    content = content:gsub("Documentar", "Document")
    content = content:gsub("Agregar", "Add")
    content = content:gsub("Crear", "Create")
    content = content:gsub("Eliminar", "Remove")
    content = content:gsub("Refactorizar", "Refactor")
    content = content:gsub("Optimizar", "Optimize")

  elseif user_language == "spanish" and current_language == "english" then
    log.debug({
      english = "Content language doesn't match configured language. Translating from English to Spanish",
      spanish = "El idioma del contenido no coincide con el idioma configurado. Traduciendo de inglés a español"
    })

    -- Realizar traducciones específicas para categorías y estados (inglés -> español)
    -- Categorías
    content = content:gsub("integration", "integración")
    content = content:gsub("validation", "validación")
    content = content:gsub("documentation", "documentación")
    content = content:gsub("interface", "interfaz")
    content = content:gsub("testing", "testing")
    content = content:gsub("format", "formato")
    content = content:gsub("refactor", "refactor")
    content = content:gsub("feature", "feature")
    content = content:gsub("implementation", "implementación")
    content = content:gsub("design", "diseño")
    content = content:gsub("security", "seguridad")
    content = content:gsub("performance", "rendimiento")
    content = content:gsub("bugs", "bugs")
    content = content:gsub("research", "investigación")
    content = content:gsub("docs", "docs")

    -- Estados
    content = content:gsub("TODO", "PENDIENTE")
    content = content:gsub("IN PROGRESS", "EN PROGRESO")
    content = content:gsub("DONE", "COMPLETADO")

    -- Resumen
    content = content:gsub("Total Tasks:", "Total Tareas:")
    content = content:gsub("Total pending:", "Total pendientes:")
    content = content:gsub("Total completed:", "Total listas:")
    content = content:gsub("%% progress:", "%% avance:")

    -- Palabras comunes en descripciones
    content = content:gsub("Implement", "Implementar")
    content = content:gsub("Review", "Revisar")
    content = content:gsub("Update", "Actualizar")
    content = content:gsub("Improve", "Mejorar")
    content = content:gsub("Validate", "Validar")
    content = content:gsub("Document", "Documentar")
    content = content:gsub("Add", "Agregar")
    content = content:gsub("Create", "Crear")
    content = content:gsub("Remove", "Eliminar")
    content = content:gsub("Refactor", "Refactorizar")
    content = content:gsub("Optimize", "Optimizar")
  end
end