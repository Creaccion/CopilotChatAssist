# Documentación para CopilotDocGitChanges

## Descripción

El comando `CopilotDocGitChanges` permite detectar y documentar elementos (funciones, métodos, clases) que han sido modificados según Git, ya sea utilizando git local o la funcionalidad `#gitdiff` de CopilotChat.

## Características

- Detecta elementos modificados utilizando diferentes métodos:
  - Git local: revisa los cambios de los últimos N commits (configurable)
  - CopilotChat: utiliza el comando `#gitdiff:origin/main..HEAD` para obtener cambios
  - CopilotChat personalizado: permite especificar un rango git personalizado (ej: `HEAD~3..HEAD`)

- Permite seleccionar elementos específicos para documentar
- Integración completa con el sistema de documentación existente

## Uso

1. Abre el archivo que deseas documentar
2. Ejecuta el comando `:CopilotDocGitChanges`
3. Selecciona el método de detección de cambios:
   - `Documentar elementos modificados (git local)`: Utiliza git del sistema
   - `Documentar elementos modificados (via CopilotChat - origin/main..HEAD)`: Utiliza CopilotChat con rango predeterminado
   - `Documentar elementos modificados (via CopilotChat - personalizado)`: Permite especificar un rango git personalizado
4. Selecciona los elementos específicos que deseas documentar del listado

## Configuración

No requiere configuración adicional. Utiliza la configuración existente del módulo de documentación.

## Ejemplo de uso

```
:CopilotDocGitChanges
```

Selecciona "Documentar elementos modificados (via CopilotChat - origin/main..HEAD)" y luego elige los elementos específicos que deseas documentar de la lista mostrada.

## Resolución de problemas

- Si no aparecen elementos modificados, verifica que realmente hay cambios en el archivo comparado con la rama principal
- Para usar la funcionalidad de CopilotChat, asegúrate de que el plugin CopilotChat esté correctamente configurado
- Si hay problemas con la detección de cambios, considera probar con diferentes métodos (local vs CopilotChat)

## Implementación técnica

El comando funciona en estas etapas:

1. Obtiene los cambios del archivo (líneas modificadas) usando git local o CopilotChat
2. Detecta los elementos (funciones, métodos, clases) en el código
3. Cruza la información para identificar qué elementos se solapan con las líneas modificadas
4. Muestra los elementos modificados para selección
5. Genera o actualiza la documentación para los elementos seleccionados

## Archivos relacionados

- `/lua/copilotchatassist/documentation/copilot_git_diff.lua`: Implementación principal
- `/lua/copilotchatassist/documentation/git_changes.lua`: Módulo para detección con git local