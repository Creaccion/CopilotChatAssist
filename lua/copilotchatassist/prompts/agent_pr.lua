-- Prompt for Pull Request generation
local M = {}

M.default = [[
Please generate a pull request description following this template:
<template>

Based on these changes:
<diff>

Return only the PR description, no extra text.
]]

return M

