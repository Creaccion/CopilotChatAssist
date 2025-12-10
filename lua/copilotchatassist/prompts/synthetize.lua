-- Prompt for synthesizing project context
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Siempre usando el lenguage ]] .. options.language .. [[ para nuestra interaccion, y el lenguaje ]] .. options.code_language .. [[ para todo lo relacionado al código, documentacion, debugs. 
Sintetiza el contexto actual del proyecto de forma autocontenida y reutilizable. Usa solo la información disponible, sin introducciones ni despedidas, y no dejes tareas pendientes.

Incluye:
- Stack tecnológico principal
- Dependencias clave
- Estructura general del proyecto (resumen de archivos relevante)
- Cambios recientes en el branch actual respecto a main
- Áreas de mejora y recomendaciones concretas
- Buenas prácticas aplicadas o sugeridas

Al final, proporciona un resumen de alto nivel del contexto detectado. Elige el formato más adecuado según el tipo de proyecto: puede ser un diagrama ASCII, un gráfico DOT, o una lista de temas principales. Este resumen debe ser claro y servir como introducción para futuras sesiones de chat.

Archivos relevantes: #glob:**/*
Cambios recientes respecto a main: #gitdiff:main..HEAD
]]

return M

