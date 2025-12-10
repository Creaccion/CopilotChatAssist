local log = require("copilotchatassist.utils.log")

-- Example agent PR function
local function agent_pr_action(msg)
  log.log("Agent PR action: " .. msg)
end

return {
  agent_pr_action = agent_pr_action
}
-- -- agent_pr.lua
-- local M = {}
-- local utils = require("copilotchatassist.utils")
--
-- function M.create_pr()
--   local current_branch = utils.get_current_branch()
--   if current_branch == "main" or current_branch == "master" then
--     vim.ui.input({ prompt = "You are on main/master. Enter new branch name: ", default = "feature/" }, function(branch_name)
--       if branch_name and branch_name ~= "" then
--         utils.switch_or_create_branch(branch_name)
--         vim.notify("Switched to branch: " .. branch_name, vim.log.levels.INFO)
--         M._create_pr_flow(branch_name)
--       else
--         vim.notify("Branch name required.", vim.log.levels.ERROR)
--       end
--     end)
--   else
--     M._create_pr_flow(current_branch)
--   end
-- end
--
-- function M.generate_pr_description()
--   local diff = utils.get_git_diff_main_head()
--   local template = utils.load_template("pr_template.txt")
--   if template == "" then
--     vim.notify("PR template not found.", vim.log.levels.ERROR)
--     return
--   end
--   local prompt = "Please generate a pull request description following this template:\n"
--     .. template .. "\n\nBased on these changes:\n" .. diff
--   -- Call CopilotChat (replace with your actual CopilotChat API call)
--   require("copilotchat").ask(prompt, function(response)
--
--     -- Show response in a read-only split
--     local buf = vim.api.nvim_create_buf(false, true)
--     vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
--     vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
--     vim.api.nvim_buf_set_option(buf, "modifiable", false)
--     vim.api.nvim_buf_set_option(buf, "readonly", true)
--     vim.cmd("botright split")
--     vim.api.nvim_win_set_buf(0, buf)
--     vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
--     vim.cmd("resize 15")
--   end)
-- end
--
-- function M.start_development()
--   vim.ui.input({ prompt = "Branch name for development: ", default = "feature/" }, function(branch_name)
--     if branch_name and branch_name ~= "" then
--       utils.switch_or_create_branch(branch_name)
--       vim.notify("Switched to branch: " .. branch_name, vim.log.levels.INFO)
--     else
--       vim.notify("Branch name required.", vim.log.levels.ERROR)
--     end
--   end)
-- end
--
-- function M._create_pr_flow(branch_name)
--   local changes = utils.get_git_diff_main_head()
--   local description = M.generate_pr_description()
--
--   utils.git_add_commit_push(description)
--   utils.create_pull_request(description)
-- end


-- vim.api.nvim_create_autocmd("BufWritePost", {
--   callback = function()
--     local current_branch = utils.get_current_branch()
--     if current_branch == "main" or current_branch == "master" then
--       require("copilotchatassist.agent_pr").start_development()
--     end
--   end,
--   group = vim.api.nvim_create_augroup("CopilotChatBranchGuard", { clear = true }),
--   desc = "Prompt for new branch if saving on main/master",
-- })
--


-- return M
--
