# Recomendaciones Detalladas de Limpieza para CopilotChatAssist

Este documento proporciona recomendaciones específicas para limpiar y simplificar el plugin CopilotChatAssist, con el objetivo de mejorar su mantenibilidad y aprovechar mejor las capacidades de CopilotChat.

## 1. Archivos a Eliminar

Los siguientes archivos pueden eliminarse por ser obsoletos, redundantes o sin uso:

```
/lua/copilotchatassist/agent_pr.lua              # Contiene solo código comentado
/lua/copilotchatassist/pr_generator.lua          # Redundante con la versión i18n
/lua/copilotchatassist/todos_functions.lua       # Consolidar en /todos/init.lua
/lua/copilotchatassist/prompts/pr_generator.lua  # Redundante con otras implementaciones de PR
/lua/copilotchatassist/utils/log_test.lua        # Archivo de prueba
```

## 2. Archivos a Consolidar

Los siguientes archivos tienen funcionalidades que podrían consolidarse para simplificar el código:

### 2.1 Prompts Relacionados con Contexto

Consolidar en un único archivo `/lua/copilotchatassist/prompts/context.lua`:
```
/lua/copilotchatassist/prompts/global_context.lua
/lua/copilotchatassist/prompts/project_context.lua
/lua/copilotchatassist/prompts/context_update.lua
/lua/copilotchatassist/prompts/synthetize.lua
```

### 2.2 Funcionalidades de Documentación

Consolidar en un único módulo `/lua/copilotchatassist/documentation.lua`:
```
/lua/copilotchatassist/doc_changes.lua
/lua/copilotchatassist/doc_review.lua
```

### 2.3 Módulos de TODOs

Consolidar en estructura más coherente:
```
/lua/copilotchatassist/todos/init.lua       # Mantener como punto de entrada
/lua/copilotchatassist/todos/window.lua     # Mantener pero refactorizar
/lua/copilotchatassist/todos_functions.lua  # Mover funcionalidad a init.lua
```

## 3. Código a Refactorizar

### 3.1 Simplificación de copilotchat_api.lua

```lua
-- Eliminar sistema de historial personalizado
M.history = {
  requests = {},
  responses = {},
  max_history = 50
}

-- Simplificar función de adición al historial
local function add_to_history(request, response)
  -- Eliminar todo este código y usar el historial nativo de CopilotChat
}

-- Refactorizar función principal para delegar más a CopilotChat
function M.ask(message, opts)
  -- Simplificar esta función para que sea una envoltura más ligera
}
```

### 3.2 Simplificación de Prompts

```lua
-- Consolidar prompts relacionados y eliminar duplicación
-- Por ejemplo, en lugar de múltiples archivos de prompt para contexto
-- crear un único módulo con funciones específicas:

local M = {}

-- Funciones específicas para diferentes tipos de contexto
M.project = function(opts)
  -- Implementación específica para contexto de proyecto
end

M.ticket = function(opts)
  -- Implementación específica para contexto de ticket
end

M.synthesis = function(opts)
  -- Implementación específica para síntesis
end

return M
```

### 3.3 Delegación de Operaciones Git

```lua
-- En lugar de funciones personalizadas como:
local function get_diff()
  local default_branch = get_default_branch()
  local cmd = string.format("git diff origin/%s...HEAD", default_branch)
  local handle = io.popen(cmd)
  local diff = handle:read("*a")
  handle:close()
  -- ... más código ...
end

-- Usar las herramientas de CopilotChat:
function M.get_diff_context()
  -- Preparar prompt que use las herramientas git de CopilotChat
  local prompt = [[
  Analyze the following git diff and provide a summary of changes:
  #gitdiff:main..HEAD
  ]]

  return copilot_api.ask(prompt, { headless = true })
end
```

## 4. Estructura Propuesta para los Comandos

Simplificar la lista de comandos y organizarlos en categorías más claras:

```lua
-- Contexto
vim.api.nvim_create_user_command("CopilotContext", function()
  require("copilotchatassist.context").get_context()
end, {})

-- TODOs
vim.api.nvim_create_user_command("CopilotTodo", function()
  require("copilotchatassist.todos").open_todo_split()
end, {})

vim.api.nvim_create_user_command("CopilotTodoGenerate", function()
  require("copilotchatassist.todos").generate_todo()
end, {})

-- PR
vim.api.nvim_create_user_command("CopilotPR", function()
  require("copilotchatassist.pr").enhance_pr()
end, {})

vim.api.nvim_create_user_command("CopilotPRLanguage", function(opts)
  local target_language = opts.args or i18n.get_current_language()
  require("copilotchatassist.pr").change_language(target_language)
end, {
  nargs = "?",
  complete = function()
    return {"english", "spanish"}
  end
})

-- Documentación
vim.api.nvim_create_user_command("CopilotDoc", function()
  require("copilotchatassist.documentation").generate()
end, {})

-- Parches
vim.api.nvim_create_user_command("CopilotPatches", function()
  require("copilotchatassist.patches").show_window()
end, {})
```

## 5. Mejoras al Procesamiento de Respuestas

### 5.1 Simplificar Procesamiento de Patches

```lua
-- Código actual complejo:
local function add_to_history(request, response)
  if #M.history.requests >= M.history.max_history then
    table.remove(M.history.requests, 1)
    table.remove(M.history.responses, 1)
  end

  table.insert(M.history.requests, request)
  table.insert(M.history.responses, response)

  -- Procesar respuesta en busca de patches
  if response and type(response) == "string" then
    local patches_module = require("copilotchatassist.patches")
    local patch_count = patches_module.process_copilot_response(response)

    if patch_count > 0 then
      vim.defer_fn(function()
        log.info({
          english = string.format("Found %d patches in the response. Use :CopilotPatchesWindow to view them.", patch_count),
          spanish = string.format("Se encontraron %d patches en la respuesta. Usa :CopilotPatchesWindow para verlos.", patch_count)
        })
      end, 500)
    end
  end
end

-- Refactorizar a:
function M.process_response(response)
  -- Proceso más simple que delega a CopilotChat cuando sea posible
  local patches_module = require("copilotchatassist.patches")
  return patches_module.process_copilot_response(response)
end
```

### 5.2 Mejorar Manejo de Errores

```lua
-- Reemplazar código como:
local success, err = pcall(function()
  -- Código largo y anidado
end)

if not success then
  log.error("Error al llamar a CopilotChat.ask: " .. tostring(err))
  vim.notify("Error al llamar a CopilotChat.ask: " .. tostring(err), vim.log.levels.ERROR)

  -- Plan B: Usar el comando directamente
  vim.notify("Intentando con el comando CopilotChat", vim.log.levels.WARN)
  vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
end

-- Con algo más simple como:
function M.safe_ask(message, opts)
  opts = opts or {}

  local ok, result = pcall(require("CopilotChat").ask, message, opts)

  if not ok then
    log.error("Failed to call CopilotChat: " .. tostring(result))
    return nil
  end

  return result
end
```

## 6. Optimizar Sistema de Prompt

### 6.1 Sistema de Prompts Dinámicos

```lua
-- Crear un sistema de prompts que permita composición y reutilización:
local prompt_system = {}

-- Componentes básicos reutilizables
prompt_system.components = {
  language_header = function()
    return string.format("Always using language %s for our interaction", options.language)
  end,

  code_language = function()
    return string.format("and language %s for everything related to code, documentation, debugging", options.code_language)
  end,

  git_diff = function(branch)
    return string.format("#gitdiff:%s..HEAD", branch or "main")
  end,
}

-- Funciones para construir prompts completos
prompt_system.build = function(components, content)
  local result = ""

  for _, component in ipairs(components) do
    if type(component) == "function" then
      result = result .. component() .. "\n"
    else
      result = result .. component .. "\n"
    end
  end

  if content then
    result = result .. content
  end

  return result
end

-- Ejemplo de uso
local ticket_context_prompt = prompt_system.build({
  prompt_system.components.language_header,
  prompt_system.components.code_language,
  "Synthesize the current ticket context including:",
  "- Main technology stack and relevant dependencies",
  "- Changes made in the branch with respect to main",
  prompt_system.components.git_diff
})
```

## 7. Migración por Fases

Se recomienda realizar la limpieza y refactorización en las siguientes fases:

### Fase 1: Limpieza Inicial (0.5 días)
- Eliminar archivos obsoletos
- Eliminar código comentado
- Consolidar funcionalidades redundantes

### Fase 2: Refactorización de API (1 día)
- Simplificar interfaz con CopilotChat
- Delegar operaciones a CopilotChat
- Mejorar manejo de errores

### Fase 3: Optimización (1 día)
- Implementar sistema de prompts mejorado
- Simplificar comandos
- Actualizar documentación

### Fase 4: Testing y Refinamiento (0.5 días)
- Verificar funcionalidad
- Ajustar según retroalimentación
- Finalizar documentación

## 8. Resumen de Beneficios

1. **Reducción de código**: Eliminación de aproximadamente el 30-40% del código actual
2. **Mayor claridad**: Estructura más coherente y mejor organizada
3. **Mantenimiento simplificado**: Menos archivos y funciones para mantener
4. **Mejor integración**: Aprovechamiento de las capacidades nativas de CopilotChat
5. **Experiencia mejorada**: Interfaz más simple y directa para el usuario

---

# Detailed Cleanup Recommendations for CopilotChatAssist

This document provides specific recommendations to clean up and simplify the CopilotChatAssist plugin, with the goal of improving its maintainability and better leveraging CopilotChat's capabilities.

## 1. Files to Remove

The following files can be removed as they are obsolete, redundant, or unused:

```
/lua/copilotchatassist/agent_pr.lua              # Contains only commented code
/lua/copilotchatassist/pr_generator.lua          # Redundant with i18n version
/lua/copilotchatassist/todos_functions.lua       # Consolidate into /todos/init.lua
/lua/copilotchatassist/prompts/pr_generator.lua  # Redundant with other PR implementations
/lua/copilotchatassist/utils/log_test.lua        # Test file
```

## 2. Files to Consolidate

The following files have functionality that could be consolidated to simplify the code:

### 2.1 Context-Related Prompts

Consolidate into a single file `/lua/copilotchatassist/prompts/context.lua`:
```
/lua/copilotchatassist/prompts/global_context.lua
/lua/copilotchatassist/prompts/project_context.lua
/lua/copilotchatassist/prompts/context_update.lua
/lua/copilotchatassist/prompts/synthetize.lua
```

### 2.2 Documentation Functionality

Consolidate into a single module `/lua/copilotchatassist/documentation.lua`:
```
/lua/copilotchatassist/doc_changes.lua
/lua/copilotchatassist/doc_review.lua
```

### 2.3 TODOs Modules

Consolidate into more coherent structure:
```
/lua/copilotchatassist/todos/init.lua       # Keep as entry point
/lua/copilotchatassist/todos/window.lua     # Keep but refactor
/lua/copilotchatassist/todos_functions.lua  # Move functionality to init.lua
```

## 3. Code to Refactor

### 3.1 Simplification of copilotchat_api.lua

```lua
-- Remove custom history system
M.history = {
  requests = {},
  responses = {},
  max_history = 50
}

-- Simplify history addition function
local function add_to_history(request, response)
  -- Remove all this code and use CopilotChat's native history
}

-- Refactor main function to delegate more to CopilotChat
function M.ask(message, opts)
  -- Simplify this function to be a lighter wrapper
}
```

### 3.2 Simplification of Prompts

```lua
-- Consolidate related prompts and eliminate duplication
-- For example, instead of multiple prompt files for context
-- create a single module with specific functions:

local M = {}

-- Specific functions for different types of context
M.project = function(opts)
  -- Specific implementation for project context
end

M.ticket = function(opts)
  -- Specific implementation for ticket context
end

M.synthesis = function(opts)
  -- Specific implementation for synthesis
end

return M
```

### 3.3 Delegation of Git Operations

```lua
-- Instead of custom functions like:
local function get_diff()
  local default_branch = get_default_branch()
  local cmd = string.format("git diff origin/%s...HEAD", default_branch)
  local handle = io.popen(cmd)
  local diff = handle:read("*a")
  handle:close()
  -- ... more code ...
end

-- Use CopilotChat tools:
function M.get_diff_context()
  -- Prepare prompt that uses CopilotChat's git tools
  local prompt = [[
  Analyze the following git diff and provide a summary of changes:
  #gitdiff:main..HEAD
  ]]

  return copilot_api.ask(prompt, { headless = true })
end
```

## 4. Proposed Structure for Commands

Simplify the list of commands and organize them into clearer categories:

```lua
-- Context
vim.api.nvim_create_user_command("CopilotContext", function()
  require("copilotchatassist.context").get_context()
end, {})

-- TODOs
vim.api.nvim_create_user_command("CopilotTodo", function()
  require("copilotchatassist.todos").open_todo_split()
end, {})

vim.api.nvim_create_user_command("CopilotTodoGenerate", function()
  require("copilotchatassist.todos").generate_todo()
end, {})

-- PR
vim.api.nvim_create_user_command("CopilotPR", function()
  require("copilotchatassist.pr").enhance_pr()
end, {})

vim.api.nvim_create_user_command("CopilotPRLanguage", function(opts)
  local target_language = opts.args or i18n.get_current_language()
  require("copilotchatassist.pr").change_language(target_language)
end, {
  nargs = "?",
  complete = function()
    return {"english", "spanish"}
  end
})

-- Documentation
vim.api.nvim_create_user_command("CopilotDoc", function()
  require("copilotchatassist.documentation").generate()
end, {})

-- Patches
vim.api.nvim_create_user_command("CopilotPatches", function()
  require("copilotchatassist.patches").show_window()
end, {})
```

## 5. Improvements to Response Processing

### 5.1 Simplify Patch Processing

```lua
-- Current complex code:
local function add_to_history(request, response)
  if #M.history.requests >= M.history.max_history then
    table.remove(M.history.requests, 1)
    table.remove(M.history.responses, 1)
  end

  table.insert(M.history.requests, request)
  table.insert(M.history.responses, response)

  -- Process response for patches
  if response and type(response) == "string" then
    local patches_module = require("copilotchatassist.patches")
    local patch_count = patches_module.process_copilot_response(response)

    if patch_count > 0 then
      vim.defer_fn(function()
        log.info({
          english = string.format("Found %d patches in the response. Use :CopilotPatchesWindow to view them.", patch_count),
          spanish = string.format("Se encontraron %d patches en la respuesta. Usa :CopilotPatchesWindow para verlos.", patch_count)
        })
      end, 500)
    end
  end
end

-- Refactor to:
function M.process_response(response)
  -- Simpler process that delegates to CopilotChat when possible
  local patches_module = require("copilotchatassist.patches")
  return patches_module.process_copilot_response(response)
end
```

### 5.2 Improve Error Handling

```lua
-- Replace code like:
local success, err = pcall(function()
  -- Long nested code
end)

if not success then
  log.error("Error al llamar a CopilotChat.ask: " .. tostring(err))
  vim.notify("Error al llamar a CopilotChat.ask: " .. tostring(err), vim.log.levels.ERROR)

  -- Plan B: Use command directly
  vim.notify("Intentando con el comando CopilotChat", vim.log.levels.WARN)
  vim.cmd("CopilotChat " .. vim.fn.shellescape(message))
end

-- With something simpler like:
function M.safe_ask(message, opts)
  opts = opts or {}

  local ok, result = pcall(require("CopilotChat").ask, message, opts)

  if not ok then
    log.error("Failed to call CopilotChat: " .. tostring(result))
    return nil
  end

  return result
end
```

## 6. Optimize Prompt System

### 6.1 Dynamic Prompt System

```lua
-- Create a prompt system that allows composition and reuse:
local prompt_system = {}

-- Reusable basic components
prompt_system.components = {
  language_header = function()
    return string.format("Always using language %s for our interaction", options.language)
  end,

  code_language = function()
    return string.format("and language %s for everything related to code, documentation, debugging", options.code_language)
  end,

  git_diff = function(branch)
    return string.format("#gitdiff:%s..HEAD", branch or "main")
  end,
}

-- Functions to build complete prompts
prompt_system.build = function(components, content)
  local result = ""

  for _, component in ipairs(components) do
    if type(component) == "function" then
      result = result .. component() .. "\n"
    else
      result = result .. component .. "\n"
    end
  end

  if content then
    result = result .. content
  end

  return result
end

-- Example usage
local ticket_context_prompt = prompt_system.build({
  prompt_system.components.language_header,
  prompt_system.components.code_language,
  "Synthesize the current ticket context including:",
  "- Main technology stack and relevant dependencies",
  "- Changes made in the branch with respect to main",
  prompt_system.components.git_diff
})
```

## 7. Phased Migration

It is recommended to perform the cleanup and refactoring in the following phases:

### Phase 1: Initial Cleanup (0.5 days)
- Remove obsolete files
- Remove commented code
- Consolidate redundant functionality

### Phase 2: API Refactoring (1 day)
- Simplify CopilotChat interface
- Delegate operations to CopilotChat
- Improve error handling

### Phase 3: Optimization (1 day)
- Implement improved prompt system
- Simplify commands
- Update documentation

### Phase 4: Testing and Refinement (0.5 days)
- Verify functionality
- Adjust based on feedback
- Finalize documentation

## 8. Summary of Benefits

1. **Code reduction**: Elimination of approximately 30-40% of current code
2. **Greater clarity**: More coherent and better organized structure
3. **Simplified maintenance**: Fewer files and functions to maintain
4. **Better integration**: Leverage CopilotChat's native capabilities
5. **Improved experience**: Simpler and more direct interface for the user