-- Prompt for Pull Request generation
local options = require("copilotchatassist.options")
local M = {}

M.default = [[
Always using language ]] .. options.language .. [[ for our interaction, and language ]] .. options.code_language .. [[ for everything related to code, documentation, debugging.
Please generate a pull request description following this template:
<template>

Based on these changes:
<diff>

Return only the PR description, no extra text.
]]

return M

