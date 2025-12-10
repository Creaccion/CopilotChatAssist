-- Prompt for enriching ticket synthesis
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Siempre usando el lenguage ]] .. options.language .. [[ para nuestra interaccion, y el lenguaje ]] .. options.code_language .. [[ para todo lo relacionado al código, documentacion, debugs. 
Enriquece la síntesis del ticket agregando:

- Tareas pendientes, numeradas y con checks
- Problemas por solucionar, con breve descripción
- Contexto actualizado según los cambios recientes
- Recomendaciones para avanzar y cerrar el ticket

Mantén la información organizada y lista para actualizar el contexto del ticket.
No incluyas introducciones ni despedidas.
]]

return M

