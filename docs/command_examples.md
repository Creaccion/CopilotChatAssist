# Ejemplos de Comandos de CopilotChatAssist

Este documento proporciona ejemplos prácticos de uso para los comandos principales del plugin CopilotChatAssist, con explicaciones paso a paso y casos de uso reales.

## Índice

- [Gestión de Contexto](#gestión-de-contexto)
- [Sistema de TODOs](#sistema-de-todos)
- [Generación de PRs](#generación-de-prs)
- [API de Lua](#api-de-lua)

## Gestión de Contexto

### Ejemplo 1: Iniciar trabajo en una nueva funcionalidad

**Escenario**: Estás empezando a trabajar en una nueva funcionalidad en la rama `feature/auth-system`.

```bash
# Cambia a la rama para la nueva funcionalidad
git checkout -b feature/auth-system
```

Abre Neovim y ejecuta:

```
:CopilotTicket
```

1. El plugin detectará la rama actual `feature/auth-system`
2. Te preguntará si deseas crear archivos de contexto para esta rama
3. Se abrirá una ventana dividida donde puedes describir el requerimiento:

```markdown
# Implementar sistema de autenticación OAuth

## Objetivo
Integrar sistema de autenticación OAuth2 con proveedores Google y GitHub.

## Requisitos
- Flujo completo de login/registro
- Gestión de sesiones con JWT
- Página de perfil de usuario
- Opción para desconectar cuentas

## Criterios de aceptación
- El usuario debe poder iniciar sesión con Google o GitHub
- El token JWT debe almacenarse de forma segura
- La sesión debe persistir al recargar la página
```

4. Guarda y cierra la ventana (`:wq`)
5. El plugin generará automáticamente:
   - Un resumen del requerimiento
   - Un análisis del contexto del proyecto
   - Una lista inicial de TODOs

### Ejemplo 2: Actualizar contexto durante el desarrollo

**Escenario**: Has estado trabajando un tiempo en la funcionalidad y quieres actualizar el contexto.

```
:CopilotUpdateContext
```

El plugin:
1. Analizará los cambios recientes (git diff)
2. Actualizará el contexto con nueva información
3. Te preguntará si deseas actualizar también los TODOs

Cuando confirmes, el contexto y los TODOs se actualizarán reflejando tu progreso.

## Sistema de TODOs

### Ejemplo 1: Generar TODOs desde el contexto

**Escenario**: Has configurado el contexto y ahora necesitas una lista de tareas.

```
:CopilotGenerateTodo
```

Esto generará un archivo Markdown similar a:

```markdown
# TODO para feature/auth-system: Implementar sistema de autenticación OAuth

| # | Status | Priority | Category | Title | Description |
|---|--------|----------|----------|-------|-------------|
| 1 | PENDING | 1 | Backend | Configurar OAuth2 | Configurar el cliente OAuth2 para Google y GitHub |
| 2 | PENDING | 1 | Backend | Implementar endpoints | Crear endpoints para login, callback y logout |
| 3 | PENDING | 2 | Frontend | Crear UI de login | Diseñar e implementar pantalla de login con botones de proveedores |
| 4 | PENDING | 2 | Frontend | Gestión de sesión | Implementar almacenamiento seguro y manejo del JWT |
| 5 | PENDING | 3 | Backend | Perfil de usuario | Endpoint para obtener y actualizar información de perfil |
| 6 | PENDING | 3 | Frontend | Página de perfil | Interfaz para ver y editar perfil de usuario |
| 7 | PENDING | 4 | Docs | Documentar API | Crear documentación para los nuevos endpoints de autenticación |

<!-- Resumen: Total: 7, Pendientes: 7, En progreso: 0, Completadas: 0, Avance: 0% -->
```

### Ejemplo 2: Trabajar con la vista de TODOs

**Escenario**: Quieres ver y gestionar tus tareas.

```
:CopilotTodoSplit
```

Se abrirá una ventana dividida con las tareas formateadas:

```
① [ ] Configurar OAuth2
② [ ] Implementar endpoints
③ [ ] Crear UI de login
③ [ ] Gestión de sesión
④ [ ] Perfil de usuario
④ [ ] Página de perfil
⑤ [ ] Documentar API
```

Interacciones en esta vista:

1. **Ver detalles de una tarea**:
   - Coloca el cursor sobre "Configurar OAuth2"
   - Presiona `Enter`
   - Se abrirá una ventana con todos los detalles

2. **Cambiar estado de una tarea**:
   - Coloca el cursor sobre "Configurar OAuth2"
   - Presiona `s` para abrir el selector de estado
   - Selecciona "in_progress"
   - La tarea se actualizará: `① [~] Configurar OAuth2`

3. **Filtrar por estado**:
   - Presiona `f`
   - Selecciona "in_progress"
   - La vista mostrará solo tareas en progreso

4. **Filtrar por prioridad**:
   - Presiona `p`
   - Selecciona "1" (prioridad alta)
   - La vista mostrará solo tareas de prioridad 1

5. **Actualizar lista de TODOs**:
   - Presiona `r`
   - La lista se regenerará basada en el contexto actual

### Ejemplo 3: Actualización de TODOs tras completar trabajo

**Escenario**: Has completado la configuración de OAuth2 y quieres actualizar el estado.

1. En la vista de TODOs:
   - Coloca el cursor sobre "Configurar OAuth2"
   - Presiona `s`
   - Selecciona "done"

2. La tarea se actualizará:
   - `① [✓] Configurar OAuth2`
   - El archivo de TODOs también se actualizará con el nuevo estado

## Generación de PRs

### Ejemplo: Generar una descripción de PR

**Escenario**: Has completado la implementación del sistema de autenticación y quieres crear un PR.

```
:CopilotEnhancePR
```

El plugin:
1. Analizará los cambios en la rama actual
2. Revisará las tareas completadas
3. Generará una descripción de PR completa:

```markdown
# Implementar sistema de autenticación OAuth

## Resumen
Este PR implementa el sistema completo de autenticación OAuth2 con soporte para proveedores Google y GitHub, incluyendo gestión de sesiones con JWT y perfil de usuario.

## Cambios realizados
- Configurado cliente OAuth2 para Google y GitHub
- Implementados endpoints de autenticación (login, callback, logout)
- Creada UI de login con soporte para múltiples proveedores
- Implementada gestión segura de tokens JWT
- Agregados endpoints para gestión de perfil de usuario
- Creada página de perfil con opciones de edición
- Documentados nuevos endpoints de API

## Pruebas realizadas
- Verificado flujo completo de login con Google
- Verificado flujo completo de login con GitHub
- Probada persistencia de sesión al recargar la página
- Validada funcionalidad de logout
- Comprobada actualización de información de perfil

## Screenshots
*Se requiere adjuntar capturas de pantalla de la nueva UI*

## Notas adicionales
Este PR completa la funcionalidad de autenticación definida en el ticket AUTH-123.
```

## API de Lua

### Ejemplo 1: Interacción programática con CopilotChat

```lua
-- Solicitar ayuda con un problema específico
require("copilotchatassist.copilotchat_api").ask([[
Estoy teniendo un problema con la autenticación OAuth. El token se recibe correctamente,
pero la sesión no persiste al recargar la página. Este es mi código actual:

```typescript
function storeToken(token: string): void {
  localStorage.setItem('auth_token', token);
}
```

¿Cómo puedo mejorar esto para garantizar que la sesión persista correctamente?
]])
```

### Ejemplo 2: Obtener asistencia con TODOs

```lua
-- Obtener sugerencias para mejorar los TODOs
local todo_content = vim.fn.readfile("/path/to/todo.md")
require("copilotchatassist.copilotchat_api").ask_todo_assistance(
  table.concat(todo_content, "\n"),
  function(response)
    -- Crear un buffer con las sugerencias
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
    vim.api.nvim_command("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
  end
)
```

### Ejemplo 3: Generar explicación detallada de una tarea

```lua
-- Definir una tarea
local task = {
  title = "Implementar sistema de permisos basado en roles",
  description = "Crear un sistema RBAC que permita asignar permisos a usuarios basados en roles",
  priority = "1",
  category = "Backend",
  status = "PENDING"
}

-- Solicitar explicación detallada
require("copilotchatassist.copilotchat_api").explain_task(task, function(response)
  -- Mostrar la explicación en una ventana flotante
  local lines = vim.split(response, "\n")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width = 80
  local height = #lines
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = 5,
    col = 10,
    style = "minimal",
    border = "rounded"
  })
end)
```

### Ejemplo 4: Integración en un flujo de trabajo personalizado

```lua
-- Función personalizada que combina varias operaciones
function workflow_nueva_feature()
  -- 1. Crear contexto para la rama actual
  require("copilotchatassist.context").copilot_tickets()

  -- 2. Generar TODOs iniciales
  require("copilotchatassist.todos").generate_todo()

  -- 3. Abrir vista dividida de TODOs
  require("copilotchatassist.todos").open_todo_split()

  -- 4. Solicitar sugerencias adicionales
  local todo_path = require("copilotchatassist.context").get_context_paths().todo_path
  local todo_content = vim.fn.readfile(todo_path)
  require("copilotchatassist.copilotchat_api").ask_todo_assistance(
    table.concat(todo_content, "\n"),
    function(response)
      vim.notify("Sugerencias para TODOs recibidas", vim.log.levels.INFO)
    end
  )
end

-- Mapear a un comando personalizado
vim.api.nvim_create_user_command("CopilotIniciarFeature", workflow_nueva_feature, {})
```