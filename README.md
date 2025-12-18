# CopilotChatAssist

CopilotChatAssist es un plugin para Neovim que actúa como una capa adicional sobre [CopilotChat](https://github.com/CopilotChat/CopilotChat.nvim), mejorando la automatización de tareas y la integración con GitHub Copilot Chat directamente desde Neovim.

## Características

- **Sistema de gestión de TODOs**: Genera, visualiza y gestiona tareas basadas en el contexto de tu proyecto.
- **Gestión contextual de trabajo**: Mantiene automáticamente el contexto de tu trabajo basado en la rama actual y los tickets.
- **Sistema de Code Review**: Analiza cambios en el Git diff y genera comentarios clasificados y accionables.
- **Indicadores de progreso visual**: Muestra el estado de operaciones largas con spinners y barras de progreso.
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
| `notification_level` | number | vim.log.levels.INFO | Nivel de las notificaciones estándar |
| `notification_timeout` | number | 2000 | Tiempo de duración de las notificaciones (ms) |
| `success_notification_level` | number | vim.log.levels.INFO | Nivel para notificaciones de éxito |
| `silent_mode` | boolean | false | Si es true, reduce el número de notificaciones mostradas |
| `use_progress_indicator` | boolean | true | Activa los indicadores visuales de progreso para operaciones largas |
| `progress_indicator_style` | string | "dots" | Estilo del indicador de progreso (dots, line, braille, circle, moon, arrow, bar) |

## Comandos

### Gestión de contexto y tickets

- `:CopilotTicket` - Abre o crea contexto para el ticket/rama actual
- `:CopilotUpdateContext` - Actualiza el contexto del proyecto y ticket
- `:CopilotProjectContext` - Genera contexto del proyecto
- `:CopilotSynthetize` - Sintetiza información del contexto

### Gestión de TODOs

- `:CopilotGenerateTodo` - Genera TODOs basados en el contexto actual
- `:CopilotTodoSplit` - Abre la ventana dividida de TODOs

### Sistema de Patches

- `:CopilotPatchesWindow` - Muestra la ventana de gestión de patches
- `:CopilotPatchesShowQueue` - Muestra resumen de la cola de patches
- `:CopilotPatchesApply` - Aplica todos los patches pendientes
- `:CopilotPatchesClearQueue` - Limpia la cola de patches
- `:CopilotPatchesProcessBuffer` - Procesa el buffer actual buscando patches

### Code Review

- `:CopilotCodeReview` - Inicia una revisión de código basada en Git diff
- `:CopilotCodeReviewList` - Muestra la lista de comentarios de la revisión
- `:CopilotCodeReviewStats` - Muestra estadísticas de la revisión actual
- `:CopilotCodeReviewExport` - Exporta la revisión a un archivo JSON
- `:CopilotCodeReviewReanalyze` - Re-analiza cambios para actualizar estado de comentarios

### Generación de documentación y PRs

- `:CopilotEnhancePR` - Genera o mejora la descripción de PR
- `:CopilotChangePRLanguage` - Cambia idioma de la descripción del PR
- `:CopilotSimplePRLanguage` - Versión simplificada para cambiar idioma del PR
- `:CopilotDocReview` - Revisa documentación actual
- `:CopilotDocChanges` - Documenta cambios recientes
- `:CopilotDocGitChanges` - Documenta elementos modificados según el diff git
- `:CopilotDocScan` - Escanea en busca de elementos sin documentación
- `:CopilotDocSync` - Sincroniza documentación (actualiza o genera)
- `:CopilotDocGenerate` - Genera documentación para el elemento en el cursor

### Visualización y estructura

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

## Arquitectura del Plugin

El plugin ha sido simplificado y reorganizado con la siguiente estructura:

### Núcleo
- **init.lua**: Punto de entrada, configuración y comandos organizados por categoría
- **copilotchat_api.lua**: API simplificada para interactuar con CopilotChat
- **options.lua**: Gestión de opciones y configuraciones

### Prompts
- **prompts/context.lua**: Sistema modular de prompts para contexto, síntesis y análisis
- **prompts/system.lua**: Prompts del sistema y plantillas base
- **prompts/todo_requests.lua**: Prompts relacionados con generación y gestión de TODOs

### Módulos funcionales
- **context.lua**: Gestión del contexto de trabajo y tickets
- **todos/**: Sistema de gestión de TODOs
- **patches.lua**: Sistema de extracción y aplicación de patches de código
- **pr_generator_i18n.lua**: Generación de descripciones de PR con soporte multiidioma

## Documentación adicional

Para más detalles sobre el uso, consulta los siguientes recursos:

- [Guía de usuario](docs/usage_examples.md) - Ejemplos detallados de uso
- [Sistema de TODOs](docs/todo_system.md) - Documentación del sistema de TODOs
- [Sistema de Patches](docs/patches_system.md) - Documentación del sistema de patches
- [Sistema de Code Review](docs/code_review_system.md) - Documentación del sistema de Code Review
- [Sistema de Progreso Visual](docs/progress_system.md) - Indicadores de progreso para operaciones largas
- [Configuración](docs/configuration.md) - Opciones de configuración detalladas
- [Estado de implementación](implementation_status.md) - Información sobre el estado actual de la simplificación
- [Resolución de problemas](docs/troubleshooting.md) - Guía de resolución de problemas

## Cambios recientes

El plugin ha sido sometido a una simplificación significativa para:

1. **Eliminar código redundante**: Consolidación de archivos y módulos similares
2. **Mejorar delegación**: Mayor aprovechamiento de las capacidades nativas de CopilotChat
3. **Optimizar estructura**: Organización más clara y modular del código
4. **Mejorar mantenibilidad**: Reducción de complejidad y duplicación

Para más detalles, consulta el [estado de implementación](implementation_status.md).

## Resolución de problemas

Si encuentras problemas con el plugin:

1. Verifica que CopilotChat esté correctamente instalado y configurado
2. Asegúrate de tener las dependencias adecuadas
3. Activa los logs de debug: `vim.g.copilotchatassist_debug = true`
4. Consulta la guía de [Resolución de problemas](docs/troubleshooting.md)

## Licencia

Este proyecto está bajo la licencia MIT.