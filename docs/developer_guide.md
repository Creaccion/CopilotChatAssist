# Developer Guide

This guide provides essential information for developers who want to contribute or extend CopilotChatAssist.

## Project Structure

```
CopilotChatAssist/
├── lua/
│   └── CopilotChat/
│       ├── init.lua
│       ├── <other modules>.lua
├── docs/
│   ├── architecture.md
│   ├── developer_guide.md
│   ├── usage_examples.md
│   └── roadmap.md
└── README.md
```

## Getting Started

1. Clone the repository and install dependencies.
2. Ensure you have CopilotChat and Copilot.vim installed.
3. Use `:CopilotChatAssist` commands in Neovim.

## Extending Functionality

- Add new Lua modules under `lua/CopilotChat/`.
- Register new commands in `init.lua`.
- Use Neovim APIs for buffer/window management.

## Testing

- Manual testing via Neovim is recommended.
- For automated tests, consider using [busted](https://olivinelabs.com/busted/) for Lua.

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Submit a pull request with a clear description.

## Coding Standards

- Use English for all code comments and documentation.
- Follow Lua best practices.
- Keep patches minimal and focused.

## Support

Open issues or discussions in the GitHub repository for help or feature requests.

