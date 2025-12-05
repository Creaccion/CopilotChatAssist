# Panel de Previsualización de Documentación

## Descripción

El Panel de Previsualización de Documentación es una característica que permite ver y seleccionar qué documentación se aplicará al código antes de realizar los cambios. Proporciona una interfaz visual que muestra:

- La documentación propuesta para cada elemento
- Si el elemento es nuevo (sin documentación previa) o se está actualizando
- Si el elemento ha sido modificado en git recientemente

Esto permite un control más granular sobre qué elementos documentar, evitando cambios no deseados.

## Características

- **Previsualización de documentación**: Ve la documentación propuesta antes de aplicarla
- **Clasificación de elementos**:
  - `[NUEVO]`: Elementos sin documentación previa
  - `[ACTUALIZAR]`: Elementos con documentación que necesita actualizarse
  - `[SIN CAMBIOS]`: Elementos con documentación que no ha cambiado
- **Integración con Git**: Identifica automáticamente los elementos modificados en git
- **Selección interactiva**: Permite seleccionar/deseleccionar elementos individuales
- **Aplicación selectiva**: Aplica documentación solo a los elementos seleccionados

## Uso

Hay varias formas de acceder al panel de previsualización:

### Desde el menú principal

1. Ejecuta `:CopilotDocSync`
2. Selecciona "Previsualizar cambios" del menú principal

### Desde las opciones avanzadas

1. Ejecuta `:CopilotDocSync`
2. Selecciona "Opciones avanzadas"
3. Selecciona "Previsualizar todos los comentarios"

## Controles del Panel

Una vez abierto el panel de previsualización, puedes usar estos controles:

- **Espacio**: Seleccionar/deseleccionar un elemento
- **Enter**: Aplicar la documentación a los elementos seleccionados
- **q**: Cerrar el panel sin aplicar cambios

## Características adicionales

### Detección de cambios en Git

El panel puede mostrar si un elemento ha sido modificado recientemente en git. Para utilizar esta característica:

1. Ejecuta `:CopilotDocSync`
2. Selecciona "Opciones avanzadas"
3. Elige "Detectar elementos modificados en git"
4. Especifica el número de commits a revisar
5. Selecciona "Previsualizar todos los comentarios"

### Visualizar todos los elementos

Para ver todos los elementos del archivo, documentados y sin documentar:

1. Ejecuta `:CopilotDocSync`
2. Selecciona "Opciones avanzadas"
3. Elige "Previsualizar todos los comentarios"

## Integración con CopilotDocGitChanges

También puedes usar el comando `:CopilotDocGitChanges` para detectar cambios usando CopilotChat con el comando `#gitdiff:origin/main..HEAD` y luego usar el panel de previsualización para revisar y seleccionar los elementos a documentar.

## Resolución de problemas

- **No aparecen elementos**: Asegúrate de que el archivo contiene elementos documentables (funciones, clases, etc.)
- **No se detectan cambios en Git**: Verifica que el archivo está en un repositorio Git y tiene cambios recientes
- **Documentación incorrecta**: Puedes deseleccionar elementos con documentación incorrecta y documentarlos manualmente