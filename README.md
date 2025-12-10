# CopilotChatAssist

CopilotChatAssist es un plugin para Neovim que actúa como una capa adicional sobre [CopilotChat](https://github.com/CopilotChat/CopilotChat.nvim), mejorando la automatización de tareas y la integración con GitHub Copilot Chat directamente desde Neovim.

## Características

- **Sistema de gestión de TODOs**: Genera, visualiza y gestiona tareas basadas en el contexto de tu proyecto.
- **Gestión contextual de trabajo**: Mantiene automáticamente el contexto de tu trabajo basado en la rama actual y los tickets.
- **Sistema de patches de código**: Extrae, visualiza y aplica automáticamente bloques de código desde CopilotChat a tus archivos.
- **Integración con Copilot**: Aprovecha la potencia de Copilot para automatizar tareas de programación.
- **Ventanas flotantes personalizables**: Visualiza información y resultados en ventanas flotantes personalizadas.
- **Filtrado de tareas**: Filtra y ordena tareas por estado, prioridad o categoría.
- **Generación de PRs**: Facilita la creación de descripciones de Pull Requests con detalles del trabajo realizado.
- **Implementación asistida**: Convierte TODOs en código funcional con la ayuda de Copilot.
- **Documentación asistida**: Ayuda con la generación y actualización de documentación de código.

## Instalación

### Requisitos previos

- Neovim 0.8.0+
- [GitHub Copilot](https://github.com/github/copilot.vim) configurado y funcionando
- [CopilotChat](https://github.com/CopilotChat/CopilotChat.nvim) instalado

### Usando lazy.nvim

```lua
{
  "ralbertomerinocolipe/CopilotChatAssist",
  dependencies = {
    "github/copilot.vim",
    { "CopilotChat/CopilotChat.nvim", branch = "canary" }  -- o la versión que uses
  },
  config = function()
    require("copilotchatassist").setup({
      language = "spanish",             -- Idioma para interacciones (español por defecto)
      code_language = "english",        -- Idioma para código generado (inglés por defecto)
      context_dir = vim.fn.expand("~/.copilot_context")  -- Directorio para archivos de contexto
    })
  end,
}
```

### Opciones de configuración

| Opción | Tipo | Valor por defecto | Descripción |
|--------|------|-------------------|-------------|
| `language` | string | "spanish" | Idioma para la comunicación con Copilot |
| `code_language` | string | "english" | Idioma para el código generado |
| `context_dir` | string | "~/.copilot_context" | Directorio para almacenar archivos de contexto |
| `model` | string | "gpt-4.1" | Modelo de lenguaje a utilizar |
| `temperature` | number | 0.1 | Temperatura para las respuestas (menor es más determinista) |
| `log_level` | number | vim.log.levels.INFO | Nivel de logs (ERROR, WARN, INFO, DEBUG, TRACE) |
| `todo_split_orientation` | string | "vertical" | Orientación de la ventana de TODOs ("vertical"/"horizontal") |

## Comandos

### Gestión de contexto y tickets

- `:CopilotTicket` - Abre o crea contexto para el ticket/rama actual
- `:CopilotUpdateContext` - Actualiza el contexto del proyecto y ticket
- `:CopilotProjectContext` - Genera contexto del proyecto

### Gestión de TODOs

- `:CopilotGenerateTodo` - Genera TODOs basados en el contexto actual
- `:CopilotTodoSplit` - Abre la ventana dividida de TODOs

### Sistema de Patches

- `:CopilotPatchesWindow` - Muestra la ventana de gestión de patches
- `:CopilotPatchesShowQueue` - Muestra resumen de la cola de patches
- `:CopilotPatchesApply` - Aplica todos los patches pendientes
- `:CopilotPatchesClearQueue` - Limpia la cola de patches
- `:CopilotPatchesProcessBuffer` - Procesa el buffer actual buscando patches

### Generación de documentación y PRs

- `:CopilotEnhancePR` - Genera o mejora la descripción de PR
- `:CopilotAgentPR` - Utiliza agente avanzado para generar PRs
- `:CopilotDocReview` - Revisa documentación actual
- `:CopilotDocChanges` - Documenta cambios recientes

### Síntesis y estructuración

- `:CopilotSynthetize` - Sintetiza información del contexto
- `:CopilotStructure` - Genera estructura de proyecto
- `:CopilotDot` - Genera diagramas en formato DOT
- `:CopilotDotPreview` - Vista previa de diagramas DOT

## Flujos de trabajo

### Ciclo de implementación de tareas

1. Inicia con `:CopilotTicket` para establecer contexto
2. Genera TODOs con `:CopilotGenerateTodo`
3. Visualiza y gestiona tareas con `:CopilotTodoSplit`
4. Selecciona una tarea y presiona `i` para implementación asistida
5. Revisa y aplica los patches generados
6. Marca las tareas como completadas
7. Genera descripción de PR con `:CopilotEnhancePR`

## Documentación adicional

Para más detalles sobre el uso, consulta los siguientes recursos:

- [Guía de usuario](docs/usage_examples.md) - Ejemplos detallados de uso
- [Sistema de TODOs](docs/todo_system.md) - Documentación del sistema de TODOs
- [Sistema de Patches](docs/patches_system.md) - Documentación del sistema de patches
- [Configuración](docs/configuration.md) - Opciones de configuración detalladas
- [Resolución de problemas](docs/troubleshooting.md) - Guía de resolución de problemas

## Resolución de problemas

Si encuentras problemas con el plugin:

1. Verifica que CopilotChat esté correctamente instalado y configurado
2. Asegúrate de tener las dependencias adecuadas
3. Activa los logs de debug: `vim.g.copilotchatassist_debug = true`
4. Consulta la guía de [Resolución de problemas](docs/troubleshooting.md)

## Licencia

Este proyecto está bajo la licencia MIT.