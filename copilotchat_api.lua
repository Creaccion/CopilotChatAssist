-- Wrapper for CopilotChat API integration

local options = require("copilotchatassist.options")

local M = {}

function M.ask(message, opts)
	opts = opts or {}
	if not opts.system_prompt then
		opts.system_prompt = options.get().system_prompt or
		    require("copilotchatassist.prompts.system").default
	end
	local CopilotChat = package.loaded["CopilotChat"] and require("CopilotChat")
	if CopilotChat and type(CopilotChat.ask) == "function" then
		CopilotChat.ask(message, opts)
	else
		vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
		if opts.callback then
			opts.callback(nil)
		end
	end
end

function M.open(context, opts)
	opts = opts or {}
	if not opts.system_prompt then
		opts.system_prompt = require("copilotchatassist.prompts.system").default
	end
	local CopilotChat = package.loaded["CopilotChat"] and require("CopilotChat")
	if CopilotChat and type(CopilotChat.open) == "function" then
		CopilotChat.open({ context = context }, opts)
	else
		vim.cmd("CopilotChat " .. vim.fn.shellescape(context))
	end
end

return M
