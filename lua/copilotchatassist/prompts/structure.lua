-- Prompt for proposing file structure
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Siempre usando el lenguage ]] .. options.language .. [[ para nuestra interaccion, y el lenguaje ]] .. options.code_language .. [[ para todo lo relacionado al código, documentacion, debugs. 
Propon una estructura de archivos para el requerimiento: <requirement>.
Usa bloques de código con path y contenido/documentación inicial.
]]

return M

