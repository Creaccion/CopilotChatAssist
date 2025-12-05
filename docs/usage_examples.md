# Guía de Usuario de CopilotChatAssist

Este documento proporciona ejemplos detallados sobre cómo utilizar las diversas funcionalidades del plugin CopilotChatAssist en tu flujo de trabajo con Neovim.

## Índice

- [Configuración Inicial](#configuración-inicial)
- [Gestión de Contexto](#gestión-de-contexto)
- [Sistema de TODOs](#sistema-de-todos)
- [Generación de PRs](#generación-de-prs)
- [Comandos de Utilidad](#comandos-de-utilidad)
- [Atajos de Teclado](#atajos-de-teclado)

## Configuración Inicial

Para comenzar con CopilotChatAssist, necesitarás configurar el plugin mediante `setup()`:

```lua
require("copilotchatassist").setup({
  language = "spanish",             -- Idioma para interacciones
  code_language = "english",        -- Idioma para código generado
  context_dir = "~/.copilot_context", -- Directorio para archivos de contexto
  log_level = vim.log.levels.INFO,  -- Nivel de logs
})
```

### Configuración Avanzada

Para usuarios avanzados que deseen personalizar la experiencia:

```lua
require("copilotchatassist").setup({
  -- Configuración básica
  language = "spanish",
  code_language = "english",
  context_dir = vim.fn.expand("~/.copilot_context"),

  -- Personalización de la visualización
  todo_split_orientation = "vertical", -- o "horizontal"

  -- Ajustes del modelo
  model = "gpt-4.1",
  temperature = 0.1,

  -- Activar logs de depuración (opcional)
  -- vim.g.copilotchatassist_debug = true,
})
```

## Gestión de Contexto

CopilotChatAssist mantiene automáticamente el contexto de tu trabajo basado en la rama actual y tickets relacionados.

### Creando un Nuevo Contexto

Para iniciar un nuevo contexto de trabajo (por ejemplo, al comenzar una nueva tarea):

```
:CopilotTicket
```

Este comando:
1. Detectará automáticamente la rama actual de git
2. Si la rama sigue el formato de ticket (ej: PROJ-123), tratará de extraer información del ticket
3. Creará archivos de contexto para almacenar información sobre la tarea actual

### Actualizando el Contexto

Para actualizar el contexto actual con cambios recientes:

```
:CopilotUpdateContext
```

## Sistema de TODOs

La funcionalidad de TODOs permite generar y administrar listas de tareas basadas en el contexto del proyecto.

### Generando TODOs

Para generar automáticamente una lista de TODOs basada en el contexto actual:

```
:CopilotGenerateTodo
```

Este comando analizará:
- El contexto del ticket/proyecto
- Los cambios recientes (git diff)
- Las tareas existentes

Y generará un archivo Markdown con tareas organizadas.

### Visualizando y Gestionando TODOs

Para abrir una ventana dividida que muestra las tareas:

```
:CopilotTodoSplit
```

Dentro de esta ventana, puedes utilizar los siguientes atajos de teclado:

- `<CR>` (Enter) - Ver detalles de la tarea seleccionada
- `r` - Actualizar/regenerar la lista de TODOs
- `f` - Filtrar tareas por estado (pendiente, en progreso, completado)
- `p` - Filtrar tareas por prioridad (1-5)
- `s` - Cambiar el estado de la tarea seleccionada
- `?` - Mostrar ayuda con todos los atajos disponibles
- `q` - Cerrar la ventana de TODOs

### Formato de TODOs

Las tareas se representan en una tabla Markdown con el siguiente formato:

```markdown
| # | Status | Priority | Category | Title | Description |
|---|--------|----------|----------|-------|-------------|
| 1 | PENDING | 1 | Core | Implementar autenticación | Integrar sistema OAuth |
| 2 | IN_PROGRESS | 2 | UI | Diseñar dashboard | Crear interfaz responsiva |
| 3 | DONE | 3 | Docs | Actualizar README | Documentar nueva API |
```

- **Status**: PENDING, IN_PROGRESS, DONE
- **Priority**: 1 (alta) a 5 (baja)
- **Category**: Categoría personalizable para la tarea
- **Title**: Título breve de la tarea
- **Description**: Descripción detallada (opcional)

## Generación de PRs

Para generar o mejorar una descripción de Pull Request:

```
:CopilotEnhancePR
```

Este comando analizará:
- El contexto actual del proyecto
- Los cambios realizados (git diff)
- Los TODOs completados

Y generará una descripción detallada para tu PR.

## Comandos de Utilidad

### Interacciones Directas con CopilotChat

Puedes interactuar directamente con CopilotChat desde el código Lua:

```lua
-- Realizar una consulta simple
require("copilotchatassist.copilotchat_api").ask("¿Cómo puedo optimizar esta función?")

-- Solicitar asistencia con TODOs
require("copilotchatassist.copilotchat_api").ask_todo_assistance(todo_content, function(response)
  -- Manejar la respuesta
end)

-- Obtener sugerencias para tareas siguientes
require("copilotchatassist.copilotchat_api").suggest_next_tasks(current_tasks, function(response)
  -- Manejar la respuesta
end)

-- Solicitar explicación sobre una tarea específica
require("copilotchatassist.copilotchat_api").explain_task(task, function(response)
  -- Manejar la respuesta
end)
```

## Atajos de Teclado

CopilotChatAssist no define atajos de teclado globales por defecto, pero puedes configurarlos fácilmente:

```lua
-- Ejemplo de mapeos personalizados
vim.keymap.set('n', '<leader>ct', ':CopilotTicket<CR>', { desc = 'Open ticket context' })
vim.keymap.set('n', '<leader>cg', ':CopilotGenerateTodo<CR>', { desc = 'Generate TODOs' })
vim.keymap.set('n', '<leader>co', ':CopilotTodoSplit<CR>', { desc = 'Open TODO split' })
vim.keymap.set('n', '<leader>cp', ':CopilotEnhancePR<CR>', { desc = 'Generate PR description' })
```

## Consejos y Trucos

### Flujo de Trabajo Recomendado

1. Inicia con `:CopilotTicket` para configurar el contexto de tu tarea
2. Genera TODOs iniciales con `:CopilotGenerateTodo`
3. Trabaja en las tareas visualizándolas con `:CopilotTodoSplit`
4. Actualiza el estado de las tareas a medida que avanzas
5. Al finalizar, genera una descripción de PR con `:CopilotEnhancePR`

### Mejores Prácticas

- Mantén el contexto actualizado para obtener mejores resultados
- Usa categorías consistentes en tus TODOs para mejor organización
- Actualiza el estado de las tareas para mantener un seguimiento preciso
- Proporciona descripciones claras para tareas complejas