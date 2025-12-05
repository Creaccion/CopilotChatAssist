# Asistente de Documentación

El Asistente de Documentación es un módulo de CopilotChatAssist diseñado para automatizar la detección, generación y actualización de documentación en el código. Utiliza CopilotChat para crear documentación inteligente que se adapta al estilo y convenciones de tu proyecto.

## Características

- **Detección automática** de funciones y métodos sin documentación
- **Generación inteligente** de documentación basada en el código
- **Actualización** de documentación desactualizada o incompleta
- **Respeto del estilo** de documentación existente en el proyecto
- **Soporte multi-lenguaje** (actualmente Lua, con otros lenguajes planificados)
- **Integración con CopilotChat** para generación de contenido de alta calidad

## Comandos

El módulo proporciona los siguientes comandos de Neovim:

- **`:CopilotDocScan`**: Escanea el buffer actual en busca de funciones sin documentación o con documentación desactualizada.
- **`:CopilotDocSync`**: Muestra un menú interactivo para actualizar la documentación del buffer actual.
- **`:CopilotDocGenerate`**: Genera o actualiza la documentación para la función bajo el cursor.

## Uso

### Escanear un archivo

Para escanear un archivo en busca de problemas de documentación:

```vim
:CopilotDocScan
```

Esto analizará el buffer actual y mostrará un resumen de los elementos detectados, clasificados en:
- Sin documentación
- Documentación desactualizada
- Documentación incompleta

### Sincronizar documentación

Para corregir los problemas de documentación detectados:

```vim
:CopilotDocSync
```

Este comando mostrará un menú interactivo con las siguientes opciones:
- **Actualizar todo**: Genera o actualiza documentación para todos los elementos detectados
- **Seleccionar elementos**: Muestra una lista de elementos para seleccionar cuáles documentar
- **Cancelar**: Cierra el menú sin realizar cambios

### Documentación bajo el cursor

Para generar o actualizar la documentación de una función específica:

```vim
:CopilotDocGenerate
```

Este comando detectará la función o clase bajo el cursor y generará o actualizará su documentación automáticamente.

## Configuración

El módulo puede configurarse en la función `setup()` de CopilotChatAssist:

```lua
require('copilotchatassist').setup({
  documentation = {
    auto_detect = false,      -- Detectar automáticamente al guardar archivos
    style_match = true,       -- Intentar hacer coincidir el estilo de documentación existente
    generate_params = true,   -- Generar documentación para parámetros
    generate_returns = true,  -- Generar documentación para valores de retorno
    include_examples = false, -- Incluir ejemplos en la documentación generada
    min_context_lines = 10,   -- Líneas de contexto mínimas a considerar
  }
})
```

### Opciones disponibles

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|----------------|-------------|
| `auto_detect` | boolean | `false` | Detecta problemas de documentación al guardar archivos |
| `style_match` | boolean | `true` | Adapta la documentación generada al estilo existente |
| `generate_params` | boolean | `true` | Incluye documentación de parámetros |
| `generate_returns` | boolean | `true` | Incluye documentación de valores de retorno |
| `include_examples` | boolean | `false` | Añade ejemplos de uso en la documentación |
| `min_context_lines` | number | `10` | Cantidad de líneas de contexto a considerar |

## Detección automática

Cuando `auto_detect` está habilitado, el plugin escanea automáticamente los archivos al guardarlos y notifica si encuentra problemas de documentación:

```lua
require('copilotchatassist').setup({
  documentation = {
    auto_detect = true
  }
})
```

## Soporte de lenguajes

Actualmente, el módulo tiene soporte nativo para:

- **Lua**: Detección y generación de documentación para funciones y métodos con soporte para el estilo de comentarios con `--`.

Se planea añadir soporte para:

- **Python**: Docstrings con formato PEP 257
- **JavaScript/TypeScript**: Documentación JSDoc
- **Otros lenguajes**: A través de un manejador común básico

## Estructura interna

El módulo está organizado en los siguientes componentes:

- **detector.lua**: Detecta problemas de documentación en el código
- **generator.lua**: Genera nueva documentación utilizando CopilotChat
- **updater.lua**: Actualiza documentación existente
- **utils.lua**: Funciones auxiliares para el manejo de documentación
- **language/**: Manejadores específicos para cada lenguaje soportado

## Ejemplos

### Generación de documentación en Lua

Para una función como:

```lua
function calculate_distance(point1, point2)
  local dx = point2.x - point1.x
  local dy = point2.y - point1.y
  return math.sqrt(dx * dx + dy * dy)
end
```

El asistente generará:

```lua
-- Calcula la distancia euclídea entre dos puntos
-- @param point1 tabla: Primer punto con coordenadas x e y
-- @param point2 tabla: Segundo punto con coordenadas x e y
-- @return número: Distancia euclídea entre los puntos
function calculate_distance(point1, point2)
  local dx = point2.x - point1.x
  local dy = point2.y - point1.y
  return math.sqrt(dx * dx + dy * dy)
end
```

## Extensibilidad

Para añadir soporte para un nuevo lenguaje, se debe crear un archivo en `lua/copilotchatassist/documentation/language/` que implemente las funciones requeridas (escaneo, detección, actualización, etc.) para ese lenguaje específico.