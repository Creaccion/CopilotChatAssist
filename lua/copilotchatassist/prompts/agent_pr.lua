-- Prompt for Pull Request generation
local options = require("copilotchatassist.options")
local M = {}

M.default = [[
Siempre usando el lenguage ]] .. options.language .. [[ para nuestra interaccion, y el lenguaje ]] .. options.code_language .. [[ para todo lo relacionado al código, documentacion, debugs. 
Please generate a pull request description following this template:
<template>

Based on these changes:
<diff>

Return only the PR description, no extra text.
]]

return M

