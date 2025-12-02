-- Wrapper for CopilotChat API integration

local options = require("copilotchatassist.options")

local M = {}

function M.ask(message, opts)
	opts = opts or {}
	if not opts.system_prompt then
		opts.system_prompt = options.get().system_prompt or
		    require("copilotchatassist.prompts.system").default
	end
	local ok, CopilotChat = pcall(require, "CopilotChat")
	if ok and CopilotChat and type(CopilotChat.open) == "function" then
		local success = pcall(function()
			CopilotChat.ask(message, opts)
		end)
		if not success then
			vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
		end
	else
		vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
	end
end

function M.open(context, opts)
	opts = opts or {}
	if not opts.system_prompt then
		opts.system_prompt = require("copilotchatassist.prompts.system").default
	end
	local ok, CopilotChat = pcall(require, "CopilotChat")
	if ok and CopilotChat and type(CopilotChat.open) == "function" then
		local success = pcall(function()
			CopilotChat.open({ context = context }, opts)
		end)
		if not success then
			vim.cmd("CopilotChat " .. vim.fn.shellescape(context))
		end
	else
		vim.cmd("CopilotChat " .. vim.fn.shellescape(context))
	end
end

return M
