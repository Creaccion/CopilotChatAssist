# Documentación Selectiva en CopilotChatAssist

## Introducción

CopilotChatAssist ahora incluye funcionalidades avanzadas para la documentación selectiva de código. Estas nuevas características permiten:

1. Detectar automáticamente elementos sin documentación
2. Identificar elementos que han cambiado recientemente en Git
3. Seleccionar específicamente qué elementos documentar
4. Filtrar elementos por estado (sin documentación, modificados, etc.)

Esta documentación describe las nuevas funcionalidades y cómo utilizarlas.

## Características Principales

### Detección de Elementos Sin Documentación

El sistema detecta automáticamente funciones, métodos, clases y otros elementos que carecen de documentación apropiada. Esto incluye:

- Elementos completamente sin documentación
- Elementos con documentación incompleta (falta documentación de parámetros, retorno, etc.)
- Elementos con documentación desactualizada (no refleja el estado actual del código)

### Identificación de Elementos Modificados en Git

Una nueva característica permite identificar elementos que han sido modificados recientemente en el historial de Git. Esto resulta especialmente útil para:

- Documentar solo el código que ha cambiado
- Mantener actualizada la documentación de elementos modificados
- Priorizar la documentación de áreas activas del código

### Selección Interactiva de Elementos

El sistema ofrece una interfaz mejorada para seleccionar específicamente qué elementos documentar:

- Lista filtrable de elementos detectados
- Indicadores visuales para elementos modificados
- Opciones para filtrar por tipo de elemento o estado
- Selección múltiple para documentar varios elementos en una sesión

### Opciones Avanzadas

Se han añadido opciones avanzadas accesibles desde el menú principal:

- **Detectar elementos modificados en Git**: Escanea el historial de Git para identificar elementos modificados
- **Documentar solo elementos modificados**: Filtra automáticamente para mostrar solo elementos cambiados
- **Documentar solo elementos sin documentación**: Filtra para mostrar solo elementos sin documentar
- **Documentar todo el archivo**: Utiliza el enfoque de documento completo para documentar todo el archivo

## Uso

### Comando Básico

Para iniciar la documentación selectiva, ejecute:

```vim
:CopilotDocSync
```

### Flujo de Trabajo

1. **Escaneo inicial**: El sistema escanea el archivo actual en busca de elementos sin documentación
2. **Selección de acción**:
   - **Actualizar todo**: Documenta todos los elementos detectados
   - **Seleccionar elementos**: Abre el selector interactivo para elegir qué documentar
   - **Opciones avanzadas**: Muestra opciones adicionales para documentación específica
   - **Cancelar**: Sale del proceso

3. **Opciones avanzadas**:
   - **Detectar elementos modificados en Git**: Solicita cuántos commits revisar y muestra elementos cambiados
   - **Documentar solo elementos modificados**: Filtra automáticamente para mostrar solo elementos cambiados
   - **Documentar solo elementos sin documentación**: Filtra para mostrar solo elementos sin documentar
   - **Documentar todo el archivo**: Utiliza el enfoque de documento completo
   - **Volver al menú principal**: Regresa al menú de acciones principal

4. **Selector interactivo**:
   - Muestra todos los elementos detectados con su estado
   - Elementos modificados recientemente se marcan con un indicador 🔄
   - Opciones de filtrado en la parte superior
   - Puede seleccionar múltiples elementos secuencialmente

### Indicadores de Estado

En el selector interactivo, los elementos se muestran con los siguientes indicadores:

- **[missing]**: Elemento completamente sin documentación
- **[outdated]**: Elemento con documentación desactualizada
- **[incomplete]**: Elemento con documentación incompleta
- **[missing 🔄]**: Elemento sin documentación que ha sido modificado recientemente
- **[outdated 🔄]**: Elemento con documentación desactualizada que ha sido modificado
- **[incomplete 🔄]**: Elemento con documentación incompleta que ha sido modificado

## Filtrado de Elementos

El selector interactivo incluye tres opciones de filtrado en la parte superior:

1. **Mostrar solo elementos modificados**: Filtra para mostrar solo elementos que han cambiado en Git
2. **Mostrar solo elementos sin documentación**: Filtra para mostrar solo elementos sin documentar
3. **Mostrar todos los elementos**: Elimina todos los filtros

## Ejemplos de Uso

### Documentar solo elementos modificados recientemente

```
:CopilotDocSync
> Opciones avanzadas
> Detectar elementos modificados en Git
> 5 (para revisar los últimos 5 commits)
> Seleccionar elementos
```

### Documentar solo elementos sin documentación

```
:CopilotDocSync
> Opciones avanzadas
> Documentar solo elementos sin documentación
```

### Documentar un archivo completo

```
:CopilotDocSync
> Opciones avanzadas
> Documentar todo el archivo
```

## Configuración

Para ajustar el comportamiento predeterminado, puede modificar las opciones en su configuración:

```lua
require('copilotchatassist').setup({
  documentation = {
    -- Usar detección selectiva en lugar de documentación completa por defecto
    use_fullfile_approach = false,

    -- Número de commits a revisar por defecto cuando se buscan cambios
    default_git_commits = 5,

    -- Incluir detección de elementos cambiados por defecto
    detect_git_changes = true
  }
})
```

## Consideraciones Técnicas

- La detección de cambios en Git requiere que el archivo esté dentro de un repositorio Git
- La detección de elementos sin documentación varía según el lenguaje de programación
- El rendimiento puede verse afectado al escanear archivos grandes o muchos commits