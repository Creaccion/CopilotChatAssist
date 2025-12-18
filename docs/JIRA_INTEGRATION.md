# Integración con Jira para CopilotChatAssist

Esta integración permite la comunicación directa entre CopilotChatAssist y Jira, facilitando la gestión de tickets y el uso de información de Jira como contexto para Copilot.

## Características

- **Cargar tickets como contexto:** Usa la información de tickets de Jira como contexto para consultas a Copilot
- **Detección automática:** Identifica tickets desde nombres de ramas Git
- **Actualización de tickets:** Añade comentarios y registra tiempo directamente desde Neovim
- **Búsqueda avanzada:** Realiza consultas JQL para encontrar tickets relevantes
- **Integración con flujo de trabajo:** Conecta tu flujo de desarrollo con el sistema de gestión de proyectos

## Configuración

### Requisitos previos

1. Una cuenta de Jira con permisos de API
2. Un token API de Jira (https://id.atlassian.com/manage-profile/security/api-tokens)
3. Curl instalado en el sistema

### Pasos de configuración

1. **Configuración manual en init.lua:**

```lua
require("copilotchatassist").setup({
  jira = {
    host = "https://tuempresa.atlassian.net", -- URL de tu instancia Jira
    email = "tu.email@empresa.com",           -- Email asociado a tu cuenta Jira
    api_token = "tu_token_api",               -- Token API generado en Atlassian
    project_key = "PROJ",                     -- Clave del proyecto predeterminado (opcional)
    auto_load = true                          -- Cargar tickets automáticamente al cambiar de rama
  }
})
```

2. **Configuración interactiva:**

Ejecuta el comando `:CopilotJiraSetup` en Neovim para configurar la integración de forma interactiva.

## Comandos disponibles

| Comando | Descripción |
|---------|-------------|
| `:CopilotJiraSetup` | Configurar integración con Jira |
| `:CopilotJiraConnect` | Comprobar conexión con Jira |
| `:CopilotJiraTicket PROJ-123` | Cargar un ticket específico como contexto |
| `:CopilotJiraDetect` | Detectar y cargar el ticket de la rama actual |
| `:CopilotJiraComment "Mi comentario"` | Añadir comentario al ticket actual |
| `:CopilotJiraTime 1h 30m Implementación` | Registrar tiempo en el ticket actual |
| `:CopilotJiraSearch "project = PROJ AND assignee = currentUser()"` | Buscar tickets usando JQL |

## Uso habitual

### Flujo de trabajo con tickets

1. **Al iniciar trabajo en un ticket:**
   ```
   :CopilotJiraDetect
   ```
   Esto detectará el ticket de tu rama actual (ej: `feature/PROJ-123-descripcion`) y cargará la información como contexto.

2. **Para consultar detalles:**
   Ahora puedes usar Copilot con el contexto del ticket para preguntar sobre requisitos, sugerencias, etc.

3. **Al completar tareas:**
   ```
   :CopilotJiraComment "He completado la implementación del componente X"
   :CopilotJiraTime 2h "Implementación y pruebas"
   ```

4. **Buscar tickets relevantes:**
   ```
   :CopilotJiraSearch "project = PROJ AND status = 'In Progress' AND assignee = currentUser()"
   ```

## Integración con el resto de CopilotChatAssist

- **Síntesis automática:** Al cargar un ticket, puedes generar una síntesis con `:CopilotTicket`
- **TODOs automáticos:** Genera TODOs basados en el ticket con `:CopilotGenerateTodo`
- **Mejora de PRs:** Incluye información del ticket en la descripción del PR con `:CopilotEnhancePR`

## Solución de problemas

### Problemas comunes

- **Error de conexión:** Verifica que las credenciales sean correctas y que tengas acceso a internet
- **Permisos insuficientes:** Confirma que tu cuenta tiene los permisos necesarios en Jira
- **Formato de rama incorrecto:** Para la detección automática, asegúrate de que tus ramas sigan el formato `PROJ-123-descripcion`

### Logs y depuración

Para activar logs detallados:

```
:CopilotLog DEBUG
```

Los logs se guardarán en el directorio de caché de Neovim.

## Personalización

Puedes personalizar el comportamiento de la integración modificando las opciones en tu configuración:

```lua
require("copilotchatassist").setup({
  jira = {
    auto_load = true,        -- Cargar ticket al cambiar de rama
    auto_update = false,     -- Actualizar Jira al guardar contexto
    cache_timeout = 300,     -- Tiempo de caché en segundos
    context_format = "detailed" -- Formato del contexto: "simple" o "detailed"
  }
})
```