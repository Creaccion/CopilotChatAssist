-- Prompt for ticket synthesis
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Siempre usando el lenguage ]] .. options.language .. [[ para nuestra interaccion, y el lenguaje ]] .. options.code_language .. [[ para todo lo relacionado al código, documentacion, debugs. 
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

