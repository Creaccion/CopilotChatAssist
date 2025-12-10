# Sistema de Gestión de TODOs

El sistema de gestión de TODOs es una de las funcionalidades principales de CopilotChatAssist, diseñado para ayudarte a organizar y gestionar tareas basadas en el contexto de tu proyecto.

## Índice

- [Conceptos clave](#conceptos-clave)
- [Generación de TODOs](#generación-de-todos)
- [Visualización de TODOs](#visualización-de-todos)
- [Interacción con tareas](#interacción-con-tareas)
- [Filtrado y búsqueda](#filtrado-y-búsqueda)
- [Flujo de trabajo recomendado](#flujo-de-trabajo-recomendado)
- [Personalización](#personalización)
- [Integración con git](#integración-con-git)

## Conceptos clave

El sistema de TODOs se basa en estos conceptos fundamentales:

1. **Tarea (Task)**: Unidad básica de trabajo con propiedades como estado, prioridad, categoría y descripción
2. **Contexto**: Información del proyecto y ticket que permite generar tareas relevantes
3. **Visualización**: Interfaces para ver y gestionar las tareas
4. **Filtrado**: Mecanismos para organizar y filtrar tareas

### Estructura de una Tarea

Cada tarea está compuesta por:

| Campo | Descripción | Valores |
|-------|-------------|---------|
| Número | Identificador numérico | Entero (1, 2, 3...) |
| Estado | Estado actual de la tarea | PENDING, IN_PROGRESS, DONE |
| Prioridad | Importancia relativa | 1-5 (1 = más alta, 5 = más baja) |
| Categoría | Tipo/área de la tarea | Personalizable (ej: "Core", "UI", "Docs") |
| Título | Descripción breve | Texto conciso (25-30 caracteres) |
| Descripción | Detalles completos | Texto, puede incluir markdown |

## Generación de TODOs

Los TODOs pueden generarse de varias maneras:

### Generación basada en contexto

El comando principal para generar TODOs es:

```
:CopilotGenerateTodo
```

Este comando:

1. Lee el archivo de requerimiento del ticket actual
2. Analiza el contexto del proyecto
3. Examina los cambios recientes en git
4. Genera una lista de tareas relevantes

### Actualización de TODOs existentes

Cuando ejecutas `:CopilotGenerateTodo` con tareas existentes:

- Las tareas existentes se mantienen
- El estado de las tareas se actualiza según los cambios (ej: tareas completadas)
- Se pueden agregar nuevas tareas basadas en cambios recientes

### Formato del archivo de TODOs

Las tareas se almacenan en un archivo Markdown con formato de tabla:

```markdown
# TODO para PROJ-123: Implementar sistema de autenticación

| # | Status | Priority | Category | Title | Description |
|---|--------|----------|----------|-------|-------------|
| 1 | PENDING | 1 | Core | Implementar login OAuth | Integrar el flujo completo de OAuth2 con el proveedor especificado |
| 2 | IN_PROGRESS | 2 | UI | Diseñar pantalla login | Crear interfaz responsiva siguiendo las guías de diseño |
| 3 | DONE | 3 | Docs | Actualizar README | Documentar proceso de autenticación |

<!-- Resumen: Total: 3, Pendientes: 1, En progreso: 1, Completadas: 1, Avance: 33.3% -->
```

## Visualización de TODOs

### Ventana dividida para TODOs

Para abrir una visualización interactiva de las tareas:

```
:CopilotTodoSplit
```

Esta interfaz proporciona:

- Vista formateada de todas las tareas
- Destacado de color según prioridad
- Iconos visuales para estados
- Interacciones mediante atajos de teclado

### Visualización compacta

En la ventana de TODOs, cada tarea se muestra en formato compacto:

```
① [✓] Implementar login OAuth
② [~] Diseñar pantalla login
③ [ ] Actualizar README
```

Donde:
- `①`, `②`, `③`, `④`, `⑤` representan la prioridad
- `[✓]`, `[~]`, `[ ]` representan el estado (completado, en progreso, pendiente)

## Interacción con tareas

Dentro de la ventana de TODOs, puedes interactuar con las tareas mediante atajos de teclado:

| Tecla | Acción |
|-------|--------|
| `<CR>` (Enter) | Ver detalles completos de la tarea |
| `r` | Actualizar/regenerar la lista de TODOs |
| `f` | Filtrar tareas por estado |
| `p` | Filtrar tareas por prioridad |
| `s` | Cambiar el estado de la tarea seleccionada |
| `?` | Mostrar ayuda con todos los atajos disponibles |
| `q` | Cerrar la ventana de TODOs |

### Vista detallada de tareas

Al presionar `Enter` en una tarea, se muestra una ventana flotante con todos los detalles:

```
Task Details

Number:      1
Status:      PENDING
Priority:    1
Category:    Core
Title:       Implementar login OAuth

Description:
Integrar el flujo completo de OAuth2 con el proveedor especificado.
Asegurar que se manejen correctamente los tokens y la sesión del usuario.
```

### Cambio de estado

Al presionar `s` sobre una tarea, se muestra un selector para cambiar su estado:
- pending
- in_progress
- done

Este cambio se guarda automáticamente en el archivo de TODOs.

## Filtrado y búsqueda

### Filtrado por estado

Presiona `f` para mostrar un selector con opciones de estado:
- all (todas)
- pending (pendientes)
- in_progress (en progreso)
- done (completadas)

### Filtrado por prioridad

Presiona `p` para mostrar un selector con opciones de prioridad:
- all (todas)
- 1 (crítica)
- 2 (alta)
- 3 (media)
- 4 (baja)
- 5 (opcional)

## Flujo de trabajo recomendado

Para aprovechar al máximo el sistema de TODOs:

1. **Inicio del proyecto/tarea**:
   - Ejecuta `:CopilotTicket` para configurar el contexto
   - Crea el archivo de requerimiento con detalles de la tarea
   - Genera TODOs iniciales con `:CopilotGenerateTodo`

2. **Durante el desarrollo**:
   - Visualiza tareas con `:CopilotTodoSplit`
   - Actualiza el estado de las tareas a medida que avanzas
   - Regenera TODOs periódicamente para incorporar cambios recientes

3. **Al finalizar**:
   - Marca todas las tareas completadas
   - Utiliza `:CopilotEnhancePR` para generar descripciones de PR basadas en el trabajo realizado

## Personalización

### Configuración de visualización

Puedes personalizar la orientación de la ventana de TODOs:

```lua
require("copilotchatassist").setup({
  todo_split_orientation = "vertical", -- o "horizontal"
})
```

### Colores y resaltado

Los colores para resaltar las prioridades de tareas se pueden personalizar:

```lua
-- Colores personalizados para prioridades de tareas
vim.api.nvim_command('highlight CopilotTodoPriority1 guifg=#ff5555 gui=bold')  -- Prioridad 1 (crítica)
vim.api.nvim_command('highlight CopilotTodoPriority2 guifg=#ffaf00 gui=bold')  -- Prioridad 2 (alta)
vim.api.nvim_command('highlight CopilotTodoPriority3 guifg=#ffd700 gui=bold')  -- Prioridad 3 (media)
vim.api.nvim_command('highlight CopilotTodoPriority4 guifg=#61afef gui=bold')  -- Prioridad 4 (baja)
vim.api.nvim_command('highlight CopilotTodoPriority5 guifg=#888888 gui=italic') -- Prioridad 5 (opcional)
```

## Integración con git

El sistema de TODOs está integrado con git para:

1. Detectar automáticamente la rama y ticket actual
2. Leer los cambios recientes para sugerir nuevas tareas
3. Actualizar el estado de tareas basado en los cambios

### Contexto de rama

El plugin detecta automáticamente la rama actual y extrae información:

- Si la rama sigue un formato de ticket (ej: PROJ-123), lo utiliza para organizar el contexto
- Si es una rama personalizada, genera un identificador único basado en el nombre

### Comandos útiles para integración

- `:CopilotUpdateContext` - Actualiza el contexto basado en los cambios recientes de git
- `:CopilotEnhancePR` - Genera descripción de PR basada en el contexto y las tareas completadas