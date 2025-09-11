-- Prompt for ticket synthesis

local M = {}

M.default = [[
Sintetiza el contexto del ticket actual incluyendo:

- Stack tecnológico principal y dependencias relevantes
- Cambios realizados en la rama respecto a main
- Requerimiento asociado y enlace a Jira (si aplica)
- Lista de tareas pendientes y avances
- Áreas de mejora y recomendaciones específicas para el ticket
- Problemas detectados y sugerencias de solución

Presenta la información de forma clara y estructurada, lista para ser reutilizada en futuras sesiones.
Responde exclusivamente en español a menos que el usuario pida explícitamente otro idioma.
]]

return M

