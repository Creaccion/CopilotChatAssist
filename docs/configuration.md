# Opciones de Configuración de CopilotChatAssist

Este documento detalla todas las opciones de configuración disponibles para personalizar el comportamiento de CopilotChatAssist según tus necesidades.

## Índice

- [Configuración básica](#configuración-básica)
- [Opciones de lenguaje](#opciones-de-lenguaje)
- [Opciones de interfaz de usuario](#opciones-de-interfaz-de-usuario)
- [Configuración del modelo](#configuración-del-modelo)
- [Opciones de TODOs](#opciones-de-todos)
- [Opciones de log y depuración](#opciones-de-log-y-depuración)
- [Configuración avanzada](#configuración-avanzada)
- [Ejemplos completos](#ejemplos-completos)

## Configuración básica

Para empezar a usar CopilotChatAssist, lo mínimo que necesitas es llamar a la función `setup`:

```lua
require("copilotchatassist").setup()
```

Esto utilizará los valores predeterminados para todas las opciones. Para personalizar el comportamiento, puedes pasar una tabla de opciones:

```lua
require("copilotchatassist").setup({
  -- Tus opciones aquí
})
```

## Opciones de lenguaje

Configura el idioma utilizado para la comunicación y el código:

| Opción | Tipo | Valor predeterminado | Descripción |
|--------|------|----------------------|-------------|
| `language` | string | "spanish" | Idioma principal para la comunicación con Copilot |
| `code_language` | string | "english" | Idioma para el código generado y comentarios |

```lua
-- Ejemplo: Configurar idiomas
require("copilotchatassist").setup({
  language = "spanish",      -- Interacción en español
  code_language = "english", -- Código en inglés
})
```

## Opciones de interfaz de usuario

Personaliza cómo se visualizan las diferentes interfaces del plugin:

| Opción | Tipo | Valor predeterminado | Descripción |
|--------|------|----------------------|-------------|
| `todo_split_orientation` | string | "vertical" | Orientación de la ventana dividida de TODOs ("vertical" o "horizontal") |
| `todo_split_width` | number | 50 | Ancho de la ventana dividida en modo vertical (porcentaje) |
| `todo_split_height` | number | 30 | Altura de la ventana dividida en modo horizontal (porcentaje) |
| `todo_highlights` | table | ver abajo | Grupos de resaltado para prioridades de tareas |

Configuración predeterminada para `todo_highlights`:

```lua
{
  [1] = "CopilotTodoPriority1", -- Prioridad 1 (crítica)
  [2] = "CopilotTodoPriority2", -- Prioridad 2 (alta)
  [3] = "CopilotTodoPriority3", -- Prioridad 3 (media)
  [4] = "CopilotTodoPriority4", -- Prioridad 4 (baja)
  [5] = "CopilotTodoPriority5", -- Prioridad 5 (opcional)
}
```

Para personalizar los colores de estas prioridades:

```lua
vim.api.nvim_command('highlight CopilotTodoPriority1 guifg=#ff5555 gui=bold')
vim.api.nvim_command('highlight CopilotTodoPriority2 guifg=#ffaf00 gui=bold')
vim.api.nvim_command('highlight CopilotTodoPriority3 guifg=#ffd700 gui=bold')
vim.api.nvim_command('highlight CopilotTodoPriority4 guifg=#61afef gui=bold')
vim.api.nvim_command('highlight CopilotTodoPriority5 guifg=#888888 gui=italic')
```

## Configuración del modelo

Ajusta los parámetros relacionados con el modelo de lenguaje:

| Opción | Tipo | Valor predeterminado | Descripción |
|--------|------|----------------------|-------------|
| `model` | string | "gpt-4.1" | Modelo de lenguaje a utilizar |
| `temperature` | number | 0.1 | Temperatura para las respuestas (0.0-1.0, menor es más determinista) |

```lua
-- Ejemplo: Configurar modelo y temperatura
require("copilotchatassist").setup({
  model = "gpt-4.1",
  temperature = 0.2,  -- Un poco más creativo que el valor predeterminado
})
```

## Opciones de TODOs

Personaliza el comportamiento del sistema de TODOs:

| Opción | Tipo | Valor predeterminado | Descripción |
|--------|------|----------------------|-------------|
| `context_dir` | string | "~/.copilot_context" | Directorio para almacenar archivos de contexto y TODOs |

```lua
-- Ejemplo: Cambiar ubicación de archivos de contexto y TODOs
require("copilotchatassist").setup({
  context_dir = vim.fn.expand("~/.local/share/nvim/copilot_context"),
})
```

## Opciones de log y depuración

Controla el nivel de detalle en los logs:

| Opción | Tipo | Valor predeterminado | Descripción |
|--------|------|----------------------|-------------|
| `log_level` | number | vim.log.levels.INFO | Nivel de logs (ERROR, WARN, INFO, DEBUG, TRACE) |

```lua
-- Ejemplo: Activar logs detallados para depuración
require("copilotchatassist").setup({
  log_level = vim.log.levels.DEBUG,
})

-- Para activar logs de depuración aún más detallados:
vim.g.copilotchatassist_debug = true
```

## Configuración avanzada

Opciones avanzadas para usuarios experimentados:

| Opción | Tipo | Valor predeterminado | Descripción |
|--------|------|----------------------|-------------|
| `system_prompt` | string | ver prompts/system.lua | Prompt del sistema que define el comportamiento del asistente |

## Ejemplos completos

### Configuración básica para desarrollo

```lua
require("copilotchatassist").setup({
  language = "spanish",
  code_language = "english",
  context_dir = vim.fn.expand("~/.copilot_context"),
  todo_split_orientation = "vertical",
  model = "gpt-4.1",
  temperature = 0.1,
  log_level = vim.log.levels.INFO,
})
```

### Configuración para depuración

```lua
-- Activar logs de depuración globales
vim.g.copilotchatassist_debug = true
vim.g.copilotchatassist_trace = true  -- Para logs aún más detallados

require("copilotchatassist").setup({
  -- Configuración básica
  language = "spanish",
  code_language = "english",

  -- Nivel de log más detallado
  log_level = vim.log.levels.DEBUG,

  -- Cambiar directorio para facilitar inspección
  context_dir = vim.fn.expand("~/Desktop/copilot_debug"),
})
```

### Configuración personalizada para TODOs

```lua
-- Personalizar colores de prioridades
vim.api.nvim_command('highlight CopilotTodoPriority1 guifg=#ff0000 gui=bold,underline')  -- Crítica (rojo)
vim.api.nvim_command('highlight CopilotTodoPriority2 guifg=#ff8800 gui=bold')           -- Alta (naranja)
vim.api.nvim_command('highlight CopilotTodoPriority3 guifg=#ffff00 gui=bold')           -- Media (amarillo)
vim.api.nvim_command('highlight CopilotTodoPriority4 guifg=#00ff00 gui=NONE')           -- Baja (verde)
vim.api.nvim_command('highlight CopilotTodoPriority5 guifg=#aaaaaa gui=italic')         -- Opcional (gris)

require("copilotchatassist").setup({
  -- Configuración de TODOs
  todo_split_orientation = "horizontal",
  todo_split_height = 20,  -- 20% de la altura de la ventana

  -- Resto de la configuración
  language = "spanish",
  code_language = "english",
  context_dir = vim.fn.expand("~/.local/share/nvim/copilot_context"),
})
```

## Solución de problemas de configuración

Si encuentras problemas con la configuración:

1. **Orden de carga**: Asegúrate de que la configuración se aplique después de cargar todos los plugins necesarios
2. **Valores inválidos**: Verifica que los valores proporcionados sean del tipo correcto
3. **Expandir rutas**: Usa siempre `vim.fn.expand()` para rutas con ~ o variables de entorno
4. **Logs de depuración**: Activa los logs de depuración para obtener más información

```lua
-- Solución de problemas: Activar logs detallados
vim.g.copilotchatassist_debug = true

-- Luego configura el plugin con valores básicos
require("copilotchatassist").setup({
  -- Solo lo esencial
  language = "spanish",
  context_dir = vim.fn.expand("~/.copilot_context"),
})
```