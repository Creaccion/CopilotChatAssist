-- Prompt for global project context analysis

local M = {}

function M.default(full_context, existing_todo)
return [[
Usa el siguiente contexto global para actualizar el archivo TODO del ticket.
- Mantén las tareas existentes en el TODO.
- Si el diff reciente sugiere nuevas tareas (por ejemplo, nuevas funciones, módulos, clases, cambios importantes), agrégalas al TODO.
- Actualiza el estado de las tareas si corresponde (por ejemplo, si el diff muestra que una tarea fue completada).
- No elimines tareas existentes a menos que estén claramente completadas.
- Formato: lista única en Markdown con tags de sección y prioridad.
- usemos formato MD y con tabla, teniendo las columnas
  - #  | status | Priority | category | description

Contexto global:
]] .. full_context .. [[

TODO actual:
]] .. existing_todo .. [[

Cambios recientes (git diff):

#gitdiff:origin/main..HEAD

Por favor, actualiza el TODO solo si es necesario, agregando nuevas tareas relevantes y actualizando el estado de las existentes.
]]
end

return M
