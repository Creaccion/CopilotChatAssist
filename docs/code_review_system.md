# Sistema de Code Review

El sistema de Code Review de CopilotChatAssist proporciona una forma eficiente de analizar y gestionar comentarios de revisión de código utilizando la potencia de GitHub Copilot.

## Características principales

- **Análisis de Git diff**: Examina automáticamente los cambios realizados en el repositorio
- **Clasificación de comentarios**: Categoriza los comentarios por tipo (Estético, Claridad, Funcionalidad, Bug, Performance, Seguridad, Mantenibilidad)
- **Niveles de severidad**: Asigna severidad a los problemas (Baja, Media, Alta, Crítica)
- **Gestión de estado**: Seguimiento del ciclo de vida de los comentarios (Abierto, Modificado, Retornado, Solucionado)
- **Persistencia**: Guarda las revisiones para referencia futura
- **Detección automática de resolución**: Identifica cuando un comentario ha sido resuelto en commits posteriores
- **Visualización flexible**: Interfaz para filtrar y visualizar comentarios por diversas categorías
- **Estadísticas**: Proporciona métricas sobre la revisión actual

## Comandos

| Comando | Descripción |
|---------|-------------|
| `:CopilotCodeReview` | Inicia una revisión de código basada en Git diff |
| `:CopilotCodeReviewList` | Muestra la lista de comentarios de la revisión |
| `:CopilotCodeReviewStats` | Muestra estadísticas de la revisión actual |
| `:CopilotCodeReviewExport` | Exporta la revisión a un archivo JSON |
| `:CopilotCodeReviewReanalyze` | Re-analiza cambios para actualizar estado de comentarios |
| `:CopilotCodeReviewReset` | Reinicia/limpia la revisión de código actual |

## Uso básico

### Iniciar una revisión

1. Realiza cambios en tu código y guárdalos
2. Ejecuta `:CopilotCodeReview` para analizar los cambios
3. Espera a que se complete el análisis

El plugin analizará el diff actual (tanto cambios staged como unstaged) y generará comentarios estructurados utilizando Copilot.

### Ver comentarios

Después de completar una revisión, se abrirá automáticamente una ventana con los comentarios. También puedes abrir esta ventana en cualquier momento con `:CopilotCodeReviewList`.

### Navegación y filtrado

En la ventana de comentarios:
- `<CR>` (Enter): Ver detalles del comentario
- `s`: Cambiar el estado del comentario
- `g`: Ir a la ubicación del comentario en el código
- `f`: Aplicar filtros (por clasificación, severidad, estado o archivo)
- `c`: Limpiar filtros
- `r`: Refrescar la ventana
- `?`: Mostrar ayuda

### Estadísticas

Visualiza estadísticas de la revisión con `:CopilotCodeReviewStats` para obtener un resumen de:
- Total de comentarios
- Distribución por severidad
- Distribución por clasificación
- Distribución por estado
- Distribución por archivo

### Re-análisis de cambios

Cuando hayas corregido problemas, puedes utilizar `:CopilotCodeReviewReanalyze` para verificar si los comentarios han sido resueltos. El sistema:

1. Analiza el nuevo diff
2. Compara con los comentarios existentes
3. Actualiza automáticamente el estado de los comentarios resueltos

### Exportación

Puedes exportar la revisión actual a un archivo JSON para compartirla o archivarla:

```
:CopilotCodeReviewExport [ruta_opcional]
```

Si no especificas una ruta, se utilizará `code_review_[timestamp].json` en el directorio actual.

## Ciclo de trabajo recomendado

1. Desarrolla tu código y realiza cambios
2. Inicia una revisión con `:CopilotCodeReview`
3. Examina los comentarios con `:CopilotCodeReviewList`
4. Soluciona los problemas empezando por los más críticos
5. Re-analiza con `:CopilotCodeReviewReanalyze` para verificar soluciones
6. Actualiza manualmente el estado de los comentarios según sea necesario
7. Repite hasta resolver todos los problemas importantes
8. Exporta la revisión si necesitas compartirla

## Clasificaciones de comentarios

- **Estético**: Relacionado con el estilo y convenciones de código
- **Claridad**: Problemas de legibilidad y comprensión
- **Funcionalidad**: Relacionado con la lógica y comportamiento
- **Bug**: Errores y comportamientos incorrectos
- **Performance**: Problemas de rendimiento
- **Seguridad**: Vulnerabilidades y riesgos de seguridad
- **Mantenibilidad**: Facilidad de mantenimiento a futuro

## Estados de comentarios

- **Abierto**: Comentario nuevo, no procesado
- **Modificado**: Se han hecho cambios pero no resuelve completamente
- **Retornado**: Se rechazó la sugerencia
- **Solucionado**: El problema ha sido resuelto

## Personalización

El sistema de Code Review utiliza la configuración general de CopilotChatAssist. Para personalizarlo, puedes modificar las opciones en tu configuración:

```lua
require("copilotchatassist").setup({
  language = "spanish",                       -- Idioma para comentarios (español por defecto)
  code_language = "english",                  -- Idioma para snippets de código (inglés por defecto)
  code_review_window_orientation = "vertical",  -- Orientación de la ventana ("vertical" u "horizontal")
  code_review_window_width = 50,              -- Ancho de la ventana cuando es vertical
  code_review_window_height = 30,             -- Alto de la ventana cuando es horizontal
  code_review_keep_window_open = true         -- Mantener ventana abierta al navegar a comentarios
})
```

## Resolución de problemas

Si encuentras problemas con el sistema de Code Review:

1. Asegúrate de que Git está configurado correctamente en tu proyecto
2. Verifica que CopilotChat está funcionando adecuadamente
3. Activa los logs de depuración con `vim.g.copilotchatassist_debug = true`
4. Comprueba los logs en `stdpath("cache") .. "/copilotchatassist/code_review_raw.txt"`