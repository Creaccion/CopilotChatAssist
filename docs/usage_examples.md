# Usage Examples

## Basic Usage

After installing the plugin, you can use the following command to interact with CopilotChat:

```
:CopilotChatAssistAsk <your question>
```

## Automating Tasks

You can automate repetitive tasks by creating custom Lua functions:

```lua
require("CopilotChatAssist").ask("Generate unit tests for this file")
```

## Integration with Quickfix

Results from CopilotChat can be sent to the quickfix list:

```lua
require("CopilotChatAssist").to_quickfix("Refactor this function")
```

See the API documentation in `lua/CopilotChat/init.lua` for more details.

