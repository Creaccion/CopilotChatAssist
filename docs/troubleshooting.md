# Guía de Resolución de Problemas

Esta guía te ayudará a diagnosticar y resolver problemas comunes que puedas encontrar al usar CopilotChatAssist.

## Índice

- [Problemas de instalación](#problemas-de-instalación)
- [Errores de inicialización](#errores-de-inicialización)
- [Problemas con CopilotChat](#problemas-con-copilotchat)
- [Problemas con el sistema de TODOs](#problemas-con-el-sistema-de-todos)
- [Problemas de contexto](#problemas-de-contexto)
- [Logs y depuración](#logs-y-depuración)
- [Problemas conocidos](#problemas-conocidos)

## Problemas de instalación

### El plugin no se carga correctamente

**Síntoma**: Neovim inicia sin errores, pero los comandos del plugin no están disponibles.

**Soluciones**:

1. **Verificar dependencias**:
   ```lua
   -- Asegúrate de que las dependencias están correctamente configuradas
   {
     "ralbertomerinocolipe/CopilotChatAssist",
     dependencies = {
       "github/copilot.vim",
       { "CopilotChat/CopilotChat.nvim", branch = "canary" }
     },
     config = function()
       require("copilotchatassist").setup()
     end,
   }
   ```

2. **Verificar rutas**:
   ```bash
   # Verifica que el plugin se ha instalado correctamente
   ls -la ~/.local/share/nvim/lazy/CopilotChatAssist
   ```

3. **Comprobar orden de carga**:
   - Asegúrate de que CopilotChat se carga antes que CopilotChatAssist

### Errores de sintaxis Lua

**Síntoma**: Errores de Lua al iniciar Neovim con mensajes sobre módulos o funciones no encontradas.

**Soluciones**:

1. **Verificar versión de Neovim**:
   ```bash
   nvim --version  # Debe ser 0.8.0 o superior
   ```

2. **Reinstalar el plugin**:
   ```
   :Lazy clean
   :Lazy sync
   ```

## Errores de inicialización

### Error: "attempt to call field '...' (a nil value)"

**Síntoma**: Errores como `attempt to call field 'debug' (a nil value)` o `attempt to call field 'truncate_string' (a nil value)`.

**Soluciones**:

1. **Activar logs de depuración**:
   ```lua
   vim.g.copilotchatassist_debug = true
   ```

2. **Verificar carga de módulos**:
   ```lua
   -- En tu init.lua, añade:
   local status, err = pcall(function()
     require("copilotchatassist").setup()
   end)
   if not status then
     vim.notify("Error cargando CopilotChatAssist: " .. err, vim.log.levels.ERROR)
   end
   ```

3. **Actualizar el plugin**:
   ```
   :Lazy update ralbertomerinocolipe/CopilotChatAssist
   ```

### Error: "No such module 'CopilotChat'"

**Síntoma**: Mensaje de error indicando que no se puede encontrar el módulo CopilotChat.

**Soluciones**:

1. **Verificar instalación de CopilotChat**:
   ```
   :Lazy check CopilotChat
   ```

2. **Revisar configuración de CopilotChat**:
   ```lua
   -- Asegúrate de que CopilotChat está configurado correctamente
   require("CopilotChat").setup({
     -- Opciones de CopilotChat
   })
   ```

3. **Verificar API key de CopilotChat**:
   - Asegúrate de tener una clave de API válida configurada para CopilotChat

## Problemas con CopilotChat

### CopilotChat no responde

**Síntoma**: Los comandos de CopilotChatAssist parecen ejecutarse, pero no hay respuesta de CopilotChat.

**Soluciones**:

1. **Verificar estado de Copilot**:
   ```
   :Copilot status
   ```

2. **Reiniciar Copilot**:
   ```
   :Copilot restart
   ```

3. **Probar CopilotChat directamente**:
   ```
   :CopilotChat ¿Estás funcionando?
   ```

4. **Revisar configuración de red**:
   - Asegúrate de tener conectividad a Internet
   - Verifica si necesitas configurar un proxy

## Problemas con el sistema de TODOs

### Los TODOs no se generan correctamente

**Síntoma**: El comando `:CopilotGenerateTodo` no produce un archivo de TODOs o el archivo está vacío.

**Soluciones**:

1. **Verificar archivos de contexto**:
   ```lua
   local context = require("copilotchatassist.context")
   local paths = context.get_context_paths()
   print(vim.inspect(paths))
   ```

2. **Comprobar permisos de directorio**:
   ```bash
   # Verificar permisos del directorio de contexto
   ls -la ~/.copilot_context
   ```

3. **Crear manualmente el directorio**:
   ```bash
   mkdir -p ~/.copilot_context
   ```

### Error al visualizar TODOs

**Síntoma**: El comando `:CopilotTodoSplit` produce errores o no muestra correctamente las tareas.

**Soluciones**:

1. **Verificar archivo de TODOs**:
   ```lua
   local context = require("copilotchatassist.context")
   local paths = context.get_context_paths()
   local todo_path = paths.todo_path
   local file_exists = vim.fn.filereadable(todo_path) == 1
   print("Archivo de TODOs existe: " .. tostring(file_exists))
   ```

2. **Regenerar TODOs**:
   ```
   :CopilotGenerateTodo
   ```

3. **Verificar formato de TODOs**:
   - Asegúrate de que el archivo tiene el formato correcto de tabla Markdown
   - Debe incluir encabezados: `| # | Status | Priority | Category | Title | Description |`

## Problemas de contexto

### No se detecta la rama git

**Síntoma**: El plugin no detecta correctamente la rama o el ticket actual.

**Soluciones**:

1. **Verificar instalación de git**:
   ```bash
   git --version
   ```

2. **Comprobar estado del repositorio**:
   ```bash
   git status
   git branch
   ```

3. **Forzar manualmente el contexto**:
   ```
   :CopilotTicket
   ```
   Y proporciona manualmente la información del ticket.

### No se encuentra el contexto del proyecto

**Síntoma**: Mensajes indicando que no se puede encontrar o cargar el contexto del proyecto.

**Soluciones**:

1. **Verificar archivos de contexto**:
   ```bash
   ls -la ~/.copilot_context
   ```

2. **Regenerar contexto del proyecto**:
   ```
   :CopilotProjectContext
   ```

3. **Comprobar ruta de contexto**:
   ```lua
   -- Asegúrate de que la ruta de contexto es correcta
   require("copilotchatassist").setup({
     context_dir = vim.fn.expand("~/.copilot_context"),
   })
   ```

## Logs y depuración

### Activar logs detallados

Para diagnosticar problemas más complejos, puedes activar logs detallados:

```lua
-- Activar logs de depuración
vim.g.copilotchatassist_debug = true

-- Para logs aún más detallados
vim.g.copilotchatassist_trace = true

-- Configurar nivel de log
require("copilotchatassist").setup({
  log_level = vim.log.levels.DEBUG,
})
```

### Verificar versiones

```lua
-- Comprobar versiones de los plugins
local plugins = {
  "CopilotChatAssist",
  "copilot.vim",
  "CopilotChat"
}

for _, plugin in ipairs(plugins) do
  local info = require("lazy.core.config").plugins[plugin]
  if info then
    print(plugin .. " version: " .. (info.version or "unknown"))
  else
    print(plugin .. " no encontrado")
  end
end
```

## Problemas conocidos

### Dependencia circular en módulos

**Síntoma**: Errores relacionados con dependencias circulares entre módulos como `options.lua` y `log.lua`.

**Solución**:
- Actualiza a la última versión del plugin, donde este problema ya está corregido
- Si persiste, puedes forzar la carga de módulos críticos al inicio:

```lua
-- Forzar precarga de módulos para evitar dependencias circulares
local _ = require("copilotchatassist.utils")
local _ = require("copilotchatassist.utils.log")
local _ = require("copilotchatassist.options")

-- Luego configura el plugin
require("copilotchatassist").setup()
```

### Problemas con la versión de CopilotChat

**Síntoma**: Incompatibilidades entre CopilotChatAssist y la versión instalada de CopilotChat.

**Solución**:
- Asegúrate de usar la versión recomendada de CopilotChat:

```lua
{
  "CopilotChat/CopilotChat.nvim",
  branch = "canary", -- Usa la versión canary
  config = function()
    require("CopilotChat").setup()
  end
}
```

## Contacto para soporte

Si después de intentar las soluciones anteriores sigues experimentando problemas:

1. Abre un issue en el repositorio: [CopilotChatAssist Issues](https://github.com/ralbertomerinocolipe/CopilotChatAssist/issues)
2. Incluye:
   - Versión de Neovim (`nvim --version`)
   - Configuración relevante
   - Logs de error completos
   - Pasos para reproducir el problema