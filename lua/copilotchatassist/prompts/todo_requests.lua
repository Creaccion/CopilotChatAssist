-- Prompt for global project context analysis
local options = require("copilotchatassist.options")
local M = {}

function M.default(full_context, existing_todo)
return [[
Siempre usando el lenguage ]] .. options.language .. [[ para nuestra interaccion y lo relacionado a los TODOS, sin traducir codigo o elementos del código
, y el lenguaje ]] .. options.code_language .. [[ para todo lo relacionado al código, documentacion, debugs. 

Usa el siguiente contexto global para actualizar el archivo TODO del ticket.
- Mantén las tareas existentes en el TODO.
- Si el diff reciente sugiere nuevas tareas (por ejemplo, nuevas funciones, módulos, clases, cambios importantes), agrégalas al TODO.
- Actualiza el estado de las tareas si corresponde (por ejemplo, si el diff muestra que una tarea fue completada).
- No elimines tareas existentes a menos que estén claramente completadas.
- Formato: lista única en Markdown con tags de sección y prioridad.
- usar nerdfonts o algun icono para el Done o TODO status, las prioridades, y Categorias

- usemos formato MD y con tabla, teniendo las columnas
  - #  | status | Priority | category | title | description

- los title deben ser muy cortos y claros, idealmente 25 caracteres y que se vea el detalle en la descripcion . 
- Terminar la tabla con el resumen: Total Tareas, Total pendientes, total listas, % avance
Contexto global:
]] .. full_context .. [[

TODO actual:
]] .. existing_todo .. [[

Cambios recientes (git diff):

#gitdiff:origin/main..HEAD

Por favor, actualiza el TODO solo si es necesario, agregando nuevas tareas relevantes y actualizando el estado de las existentes.
Devuelve únicamente la tabla Markdown con las tareas, sin ningún encabezado, bloque de código, comentario, ni texto adicional antes o después. No incluyas leyendas ni explicaciones. Solo la tabla.

]]
end

return M
