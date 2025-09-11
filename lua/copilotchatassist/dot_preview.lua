local log = require("copilotchatassist.utils.log")

-- Example dot preview function
local function dot_preview_action(msg)
  log.log("Dot preview: " .. msg)
end

return {
  dot_preview_action = dot_preview_action,
}
--
-- local M = {}
--
-- -- Genera PNG desde DOT y lo muestra en un panel flotante usando viu
-- function M.preview_dot_with_viu()
--   local dot_file = vim.fn.expand('%:p')
--   if not dot_file:match('%.dot$') then
--     vim.notify("No es un archivo .dot", vim.log.levels.WARN)
--     return
--   end
--   local png_file = "/tmp/neovim_dot_preview.png"
--   local cmd = string.format("dot -Tpng %s -o %s", vim.fn.shellescape(dot_file), png_file)
--   local result = os.execute(cmd)
--   if result ~= 0 then
--     vim.notify("Error al generar PNG con dot", vim.log.levels.ERROR)
--     return
--   end
--
--   -- Abre un terminal flotante y ejecuta viu
--   local Terminal  = require('toggleterm.terminal').Terminal
--   local viu_term = Terminal:new({
--     cmd = "viu " .. png_file .. "; read -n 1 -s -r -p 'Presiona una tecla para cerrar...'",
--     direction = "float",
--     close_on_exit = true,
--     on_open = function(term)
--       vim.api.nvim_buf_set_keymap(term.bufnr, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
--     end,
--   })
--   viu_term:toggle()
-- end
--
-- return M
