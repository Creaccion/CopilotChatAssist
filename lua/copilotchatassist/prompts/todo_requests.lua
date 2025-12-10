-- Prompt for global project context analysis
local options = require("copilotchatassist.options")
local M = {}

local log = require("copilotchatassist.utils.log")

function M.default(full_context, ticket_context, existing_todo)
  -- Get current option values
  local user_language = options.get().language or "english"
  local code_language = options.get().code_language or "lua"

  log.debug({
    english = "Using language for TODOs: " .. user_language,
    spanish = "Usando idioma para TODOs: " .. user_language
  })

  -- Create the start of the prompt with actual language values inserted
  local prompt_start = string.format([[Always using language %s for our interaction and everything related to TODOs, without translating code or code elements, and language %s for everything related to code, documentation, debugging.]], user_language, code_language)

  -- Adapt labels based on the language
  local status_labels = {
    todo = (user_language:lower() == "spanish") and "PENDIENTE" or "TODO",
    in_progress = (user_language:lower() == "spanish") and "EN PROGRESO" or "IN PROGRESS",
    done = (user_language:lower() == "spanish") and "COMPLETADO" or "DONE"
  }

  -- Build status labels based on language
  local status_text = string.format([[For status, use words only, standardizing them for later parsing, %s, %s, %s]],
    status_labels.done, status_labels.in_progress, status_labels.todo)

  -- Define messages based on language
  local prompt_messages = {}
  if user_language:lower() == "spanish" then
    prompt_messages = {
      update_context = "Usa el siguiente contexto global para actualizar el archivo TODO del ticket.",
      tasks_related = "- Las tareas deben estar relacionadas con el contexto del ticket, no con el contexto completo",
      keep_tasks = "- Mantén las tareas existentes en el TODO.",
      add_new = "- Si el diff reciente sugiere nuevas tareas (por ejemplo, nuevas funciones, módulos, clases, cambios importantes), agrégalas al TODO.",
      update_status = "- Actualiza el estado de las tareas si corresponde (por ejemplo, si el diff muestra que una tarea fue completada).",
      dont_remove = "- No elimines tareas existentes a menos que estén claramente completadas.",
      format = "- Formato: lista única en Markdown con tags de sección y prioridad.",
      order = "- Que el orden sea, de arriba a abajo: - in progress, todo, done, y en segundo nivel la prioridad, arriba lo mas prioritario",
      priority = "- la prioridad debe ser numerica de 1 a 5, siendo 1 lo mas importante",
      md_format = "- usemos formato MD y con tabla, teniendo las columnas",
      columns = "  - #  | status | Priority | category | title | description",
      titles = "- los title deben ser muy cortos y claros, idealmente 25 caracteres y que se vea el detalle en la descripcion .",
      summary = "- Terminar la tabla con el resumen: Total Tareas, Total pendientes, total listas, % avance",
      ticket_context = "Contexto ticket:",
      global_context = "Contexto global:",
      current_todo = "TODO actual:",
      recent_changes = "Cambios recientes (git diff):",
      git_diff = "#gitdiff:origin/main..HEAD",
      update_request = "Por favor, actualiza el TODO solo si es necesario, agregando nuevas tareas relevantes y actualizando el estado de las existentes.",
      return_only = "Devuelve únicamente la tabla Markdown con las tareas, sin ningún encabezado, bloque de código, comentario, ni texto adicional antes o después. No incluyas leyendas ni explicaciones. Solo la tabla."
    }
  else
    prompt_messages = {
      update_context = "Use the following global context to update the ticket's TODO file.",
      tasks_related = "- Tasks must be related to the ticket context, not to the complete context",
      keep_tasks = "- Keep existing tasks in the TODO.",
      add_new = "- If recent diff suggests new tasks (e.g., new functions, modules, classes, important changes), add them to the TODO.",
      update_status = "- Update the status of tasks as needed (e.g., if the diff shows a task was completed).",
      dont_remove = "- Do not delete existing tasks unless they are clearly completed.",
      format = "- Format: single Markdown list with section and priority tags.",
      order = "- The order should be, from top to bottom: - in progress, todo, done, and at a second level the priority, with most important tasks at the top",
      priority = "- Priority should be numeric from 1 to 5, with 1 being the most important",
      md_format = "- Let's use MD format with a table, having columns",
      columns = "  - #  | status | Priority | category | title | description",
      titles = "- Titles should be very short and clear, ideally 25 characters, with details visible in the description.",
      summary = "- End the table with the summary: Total Tasks, Total pending, Total completed, % progress",
      ticket_context = "Ticket context:",
      global_context = "Global context:",
      current_todo = "Current TODO:",
      recent_changes = "Recent changes (git diff):",
      git_diff = "#gitdiff:origin/main..HEAD",
      update_request = "Please update the TODO only if necessary, adding relevant new tasks and updating the status of existing ones.",
      return_only = "Return only the Markdown table with the tasks, without any header, code block, comment, or additional text before or after. Do not include captions or explanations. Just the table."
    }
  end

  return prompt_start .. [[

]] .. prompt_messages.update_context .. [[
]] .. prompt_messages.tasks_related .. [[
]] .. prompt_messages.keep_tasks .. [[
]] .. prompt_messages.add_new .. [[
]] .. prompt_messages.update_status .. [[
]] .. prompt_messages.dont_remove .. [[
]] .. prompt_messages.format .. [[
]] .. status_text .. [[
]] .. prompt_messages.order .. [[
]] .. prompt_messages.priority .. [[

]] .. prompt_messages.md_format .. [[
]] .. prompt_messages.columns .. [[

]] .. prompt_messages.titles .. [[
]] .. prompt_messages.summary .. [[

]] .. prompt_messages.ticket_context .. [[
]] .. ticket_context .. [[
]] .. prompt_messages.global_context .. [[
]] .. full_context .. [[

]] .. prompt_messages.current_todo .. [[
]] .. existing_todo .. [[

]] .. prompt_messages.recent_changes .. [[

]] .. prompt_messages.git_diff .. [[

]] .. prompt_messages.update_request .. [[
]] .. prompt_messages.return_only .. [[

]]
end

return M
