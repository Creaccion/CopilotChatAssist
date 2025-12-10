# Sistema de Patches de Código para CopilotChatAssist

Este módulo permite a CopilotChatAssist detectar, gestionar y aplicar bloques de código (patches) generados por CopilotChat a archivos de tu proyecto.

## Características principales

- Detección automática de patches en respuestas de CopilotChat
- Gestión de cola centralizada de patches pendientes
- Interfaz visual para previsualizar y aplicar patches
- Integración con el sistema de TODOs
- Diferentes modos de aplicación de código (reemplazar, insertar, añadir, eliminar)

## Comandos disponibles

- `:CopilotPatchesWindow` - Muestra la ventana de patches pendientes
- `:CopilotPatchesClearQueue` - Limpia la cola de patches pendientes
- `:CopilotPatchesApply` - Aplica todos los patches de la cola
- `:CopilotPatchesProcessBuffer` - Procesa el buffer actual buscando patches

## Uso con sistema de TODOs

El sistema de patches está integrado con el módulo de TODOs, permitiendo:

1. Seleccionar una tarea en la vista de TODOs
2. Presionar `i` para solicitar implementación a CopilotChat
3. Los patches generados se añaden automáticamente a la cola
4. Ver y aplicar los patches desde la interfaz visual

## Formato de patches

Los patches deben tener el siguiente formato en las respuestas de CopilotChat:

```<lenguaje> path=/ruta/al/archivo start_line=<num> end_line=<num> mode=<modo>
// código aquí
```end

Donde:
- `<lenguaje>`: Lenguaje del código (ej: javascript, python, lua)
- `path`: Ruta absoluta al archivo (obligatoria)
- `start_line`, `end_line`: Líneas de inicio y fin (números)
- `mode`: Modo de aplicación:
  - `replace`: Reemplaza las líneas indicadas
  - `insert`: Inserta en la posición indicada
  - `append`: Añade después de la línea indicada
  - `delete`: Elimina las líneas indicadas

## Archivos y módulos

- `patches/init.lua`: Punto de entrada principal y API pública
- `patches/parser.lua`: Parseo y validación de bloques de patch
- `patches/queue.lua`: Gestión de la cola de patches pendientes
- `patches/file_manager.lua`: Aplicación segura de patches a archivos
- `patches/window.lua`: Interfaz visual para gestionar patches

## Ejemplos de uso

### Uso básico desde código Lua

```lua
-- Procesar respuesta de CopilotChat para extraer patches
local response = "... respuesta con patches ..."
local patches = require("copilotchatassist.patches")
local count = patches.process_copilot_response(response)

-- Mostrar interfaz visual de patches
patches.show_patch_window()

-- Aplicar todos los patches
patches.apply_patch_queue()
```

### Solicitar implementación de una tarea

```lua
-- Desde cualquier parte del código
local copilot_api = require("copilotchatassist.copilotchat_api")
local task = {
  title = "Implementar sistema de login",
  description = "Crear función de autenticación con JWT",
  category = "Backend",
  priority = 1
}
copilot_api.implement_task(task)
```

## Configuración

El sistema de patches se inicializa automáticamente con CopilotChatAssist, pero puedes configurar algunas opciones:

```lua
-- En tu setup de CopilotChatAssist
require("copilotchatassist").setup({
  -- Opciones para patches (próximamente)
})
```