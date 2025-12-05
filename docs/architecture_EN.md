# CopilotChatAssist Architecture

This document provides a detailed overview of the CopilotChatAssist plugin architecture, components, and workflows. This plugin enhances Neovim by integrating with GitHub Copilot Chat to provide advanced features for code documentation, PR descriptions, TODO management, and more.

## System Overview

CopilotChatAssist is organized as a modular Neovim plugin that integrates with the CopilotChat plugin to leverage AI capabilities for various development tasks. The architecture follows these key principles:

- **Modularity**: Functionality is separated into logical components
- **I18n Support**: Multilingual interface in English and Spanish
- **Context-Awareness**: Maintains project and ticket context to enhance AI interactions
- **Extensibility**: Designed to easily add new features and language support

![Architecture Overview](./images/architecture_diagram.svg)

## Core Components

### 1. CopilotChat API Integration (`copilotchat_api.lua`)

Acts as a wrapper around CopilotChat functionality, providing:
- Request handling and formatting
- Response processing with history tracking
- Error handling and fallback mechanisms
- Patch extraction from AI responses

```lua
-- Example: Making a request to CopilotChat
copilot_api.ask(prompt, {
  headless = true,
  callback = function(response)
    -- Process the response
    -- Extract patches if present
  end
})
```

### 2. Context System (`context.lua`)

Manages project and ticket context information:
- Tracks active context/ticket
- Maintains context files
- Associates TODOs with specific contexts
- Updates context based on user input and git changes

```lua
-- Example: Context file structure
{
  project_context = "/path/to/project_context.md",
  synthesis = "/path/to/ticket_synthesis.md",
  requirement = "/path/to/requirement.md",
  todo_path = "/path/to/TODO_context.md"
}
```

### 3. TODO System (`todos/init.lua`, `todos/window.lua`)

Provides functionality for managing task lists:
- Per-context TODO files
- Interactive UI for task management
- Status tracking (pending, in_progress, done)
- Priority management
- Automatic updates based on git changes

![TODO System Workflow](./images/todo_workflow.svg)

Key features:
- Interactive split window for managing TODOs
- Color-coded priorities
- Status filtering
- Task implementation assistance

### 4. PR Generator (`pr_generator_i18n.lua`, `pr_generator.lua`)

Generates and enhances pull request descriptions:
- Analyzes git diffs
- Incorporates commit messages
- Creates structured PR descriptions
- Supports multilingual output
- Generates Mermaid diagrams

![PR Enhancement System](./images/pr_enhancement.svg)

### 5. Documentation System (`documentation/` directory)

Comprehensive system for code documentation:
- Language-specific documentation generators
- Automatic detection of undocumented elements
- Documentation previewing and application
- Git integration for documenting changed code

![Documentation System](./images/documentation_system.svg)

Supported languages:
- Java (JavaDoc)
- Lua (LDoc)
- Ruby (YARD)
- Elixir (ExDoc)
- YAML, HCL, Shell, and more

### 6. Patches System (`patches/` directory)

Processes code suggestions from CopilotChat:
- Parses code blocks with metadata
- Creates applicable code patches
- Provides preview and application UI
- Maintains a patch queue

### 7. I18n System (`i18n.lua`)

Provides internationalization support:
- English and Spanish interfaces
- Translated prompts for AI
- Language detection and configuration

## Workflow Integration

CopilotChatAssist integrates with the following common developer workflows:

### 1. Ticket/Task Implementation Workflow

1. User creates or selects a context/ticket
2. System generates TODO file associated with context
3. User works through TODOs, updating status as they go
4. System automatically updates context based on progress
5. Git changes trigger context/TODO updates

### 2. Documentation Workflow

1. User opens a file for documentation
2. System scans for undocumented elements
3. User selects elements to document
4. System generates documentation using CopilotChat
5. User reviews and applies documentation

### 3. PR Creation Workflow

1. User completes implementation and commits changes
2. User invokes PR enhancement command
3. System analyzes diffs, commits, and context
4. CopilotChat generates PR description with sections
5. System updates GitHub PR description
6. Optional language switching for multilingual teams

## File Structure

```
CopilotChatAssist/
├── lua/copilotchatassist/
│   ├── init.lua               # Plugin initialization
│   ├── commands.lua           # Command registration
│   ├── options.lua            # Configuration options
│   ├── context.lua            # Context management
│   ├── copilotchat_api.lua    # CopilotChat integration
│   ├── i18n.lua               # Internationalization
│   ├── prompts/               # AI prompt templates
│   ├── documentation/         # Documentation system
│   │   ├── init.lua           # Main documentation module
│   │   ├── detector.lua       # Code element detector
│   │   ├── generator.lua      # Doc generation logic
│   │   ├── language/          # Language-specific handlers
│   │   └── ...
│   ├── patches/               # Patches system
│   │   ├── init.lua           # Main patches module
│   │   ├── parser.lua         # Code block parser
│   │   └── ...
│   ├── todos/                 # TODO management
│   │   ├── init.lua           # Main TODO module
│   │   └── window.lua         # TODO UI
│   └── utils/                 # Utility functions
├── docs/                      # Documentation
└── test/                      # Test files
```

## Extensibility

CopilotChatAssist is designed to be extended in several ways:

### Adding New Language Support

To add support for a new programming language in the documentation system:

1. Create a new file in `documentation/language/`
2. Implement detection patterns for undocumented elements
3. Define documentation format templates
4. Register the language in the documentation system

### Adding New Commands

To add new commands:

1. Define the command function in an appropriate module
2. Register it in `init.lua` using `vim.api.nvim_create_user_command()`
3. Add any necessary prompt templates in `prompts/`

## Configuration

The plugin can be configured through the `setup()` function:

```lua
require('copilotchatassist').setup({
  language = "english",      -- Interface language
  code_language = "english", -- Documentation language
  log_level = "INFO",        -- Logging verbosity
  todo_split_orientation = "vertical", -- TODO window orientation
  -- Additional configuration...
})
```

## Performance Considerations

- The plugin uses asynchronous operations where possible to avoid blocking the UI
- Large requests to CopilotChat are chunked to avoid timeouts
- Background processing for patch application
- Lazy-loading of less frequently used modules

## Security Considerations

- No sensitive data is sent to CopilotChat by default
- Debug logs are stored locally in the Neovim cache directory
- No automatic code changes are applied without user confirmation