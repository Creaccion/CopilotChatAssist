# Architecture Overview

CopilotChatAssist is designed to wrap CopilotChat functionality and expose it through Neovim commands and Lua APIs.

## High-Level Diagram

```
+-------------------------+
|     Neovim User         |
+-------------------------+
            |
            v
+-------------------------+
|   CopilotChatAssist     |
|  (Lua Plugin Layer)     |
+-------------------------+
            |
            v
+-------------------------+
|    CopilotChat Plugin   |
+-------------------------+
            |
            v
+-------------------------+
|   GitHub Copilot Chat   |
+-------------------------+
```

## Main Components

- **CopilotChatAssist**: Handles Neovim integration, user commands, and automation logic.
- **CopilotChat**: Provides chat and code completion features.
- **Neovim Core**: Buffers, windows, quickfix, etc.

## Data Flow

User actions in Neovim trigger CopilotChatAssist commands, which interact with CopilotChat and display results in Neovim buffers or windows.

