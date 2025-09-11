# CopilotChatAssist

CopilotChatAssist is a Neovim plugin that acts as a wrapper for CopilotChat, enabling automation of tasks and seamless interaction with GitHub Copilot Chat from within Neovim.

## Features

- Automate CopilotChat tasks directly from Neovim.
- Customizable commands and workflows.
- Integration with Neovim buffers, windows, and quickfix lists.
- Extensible for advanced developer workflows.

## Installation

Use your preferred plugin manager. Example with `lazy.nvim`:

```lua
{
  "ralbertomerinocolipe/CopilotChatAssist",
  dependencies = { "github/copilot.vim", "CopilotChat" },
  config = function()
    require("CopilotChatAssist").setup()
  end,
}
```

## Usage

After installation, use the provided commands to interact with CopilotChat. See [docs/usage_examples.md](docs/usage_examples.md) for details.

## Developer Documentation

See the [docs/](docs/) folder for architecture, developer guide, and roadmap.

## Next Steps

- See [docs/roadmap.md](docs/roadmap.md) for planned features and improvements.

