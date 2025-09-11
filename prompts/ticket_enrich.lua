-- Prompt for enriching ticket synthesis

local M = {}

M.default = [[
Enriquece la síntesis del ticket agregando:

- Tareas pendientes, numeradas y con checks
- Problemas por solucionar, con breve descripción
- Contexto actualizado según los cambios recientes
- Recomendaciones para avanzar y cerrar el ticket

Mantén la información organizada y lista para actualizar el contexto del ticket.
No incluyas introducciones ni despedidas.
]]

return M

