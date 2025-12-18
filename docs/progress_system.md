# Sistema de Progreso Visual

Este documento describe el sistema de indicadores visuales de progreso implementado en CopilotChatAssist para mostrar feedback durante operaciones de larga duración.

## Descripción General

El sistema de progreso visual proporciona dos tipos principales de indicadores:

1. **Spinners** (indicadores giratorios): Muestran actividad durante operaciones asíncronas sin un progreso cuantificable.
2. **Barras de progreso**: Visualizan el porcentaje completado en operaciones donde se puede medir el avance.

Los indicadores pueden mostrarse en la línea de estado de Neovim o en ventanas flotantes dedicadas, según la configuración y el contexto.

## Configuración

El sistema de progreso se configura en el archivo `options.lua` con las siguientes opciones:

| Opción | Tipo | Valor por defecto | Descripción |
|--------|------|-------------------|-------------|
| `use_progress_indicator` | boolean | true | Activa o desactiva el sistema de progreso visual |
| `progress_indicator_style` | string | "dots" | Estilo visual del spinner: "dots", "line", "braille", "circle", "moon", "arrow", "bar" |

Ejemplo de configuración:

```lua
require("copilotchatassist").setup({
  use_progress_indicator = true,
  progress_indicator_style = "braille",
})
```

## Estilos de Spinners Disponibles

El módulo incluye varios estilos visuales para los spinners:

- **dots**: `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` (predeterminado)
- **line**: `| / - \`
- **braille**: `⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷`
- **circle**: `◜ ◠ ◝ ◞ ◡ ◟`
- **moon**: `🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘`
- **arrow**: `▹▹▹▹▹ ▸▹▹▹▹ ▹▸▹▹▹ ▹▹▸▹▹ ▹▹▹▸▹ ▹▹▹▹▸`
- **bar**: `[     ] [=    ] [==   ] [===  ] [==== ] [=====]`

## API del Sistema de Progreso

El módulo `utils/progress.lua` proporciona las siguientes funciones principales:

### Spinners

```lua
-- Inicia un spinner con un ID único
progress.start_spinner(id, message, opts)

-- Detiene un spinner por su ID
progress.stop_spinner(id, success)

-- Actualiza el mensaje de un spinner existente
progress.update_spinner(id, message)
```

Parámetros:
- `id`: Identificador único para el spinner
- `message`: Mensaje a mostrar junto al spinner
- `success`: Booleano opcional para indicar si la operación fue exitosa
- `opts`: Tabla de opciones (style, position, speed, etc.)

### Barras de progreso

```lua
-- Muestra una barra de progreso
progress.show_progress_bar(title, percentage, opts)

-- Cierra la barra de progreso
progress.close_progress_bar()
```

Parámetros:
- `title`: Título para la barra de progreso
- `percentage`: Porcentaje completado (0-100)
- `opts`: Tabla de opciones (width, etc.)

## Integración con Funcionalidades Existentes

El sistema de progreso está integrado con varias funcionalidades clave:

### Mejora de Descripciones de PR

```lua
-- En pr_generator_i18n.lua
local progress = require("copilotchatassist.utils.progress")
local spinner_id = "enhance_pr"
progress.start_spinner(spinner_id, "Enhancing PR description", {
  style = options.get().progress_indicator_style,
  position = "statusline"
})

-- Más tarde, detener el spinner basado en la respuesta
local success = response ~= nil
progress.stop_spinner(spinner_id, success)
```

### Traducción de Descripciones de PR

```lua
-- En pr_generator_i18n.lua (función simple_change_pr_language)
local message = "Translating PR from " .. current_detected_language .. " to " .. target_language
progress.start_spinner(spinner_id, message, {
  style = options.get().progress_indicator_style,
  position = "statusline"
})
```

## Ejemplos de Uso

### Spinner básico

```lua
local progress = require("copilotchatassist.utils.progress")

-- Iniciar un spinner para una operación larga
local spinner_id = "my_operation"
progress.start_spinner(spinner_id, "Procesando datos", {
  style = "dots",
  position = "statusline"
})

-- Simular una operación larga
vim.defer_fn(function()
  -- Actualizar el mensaje durante la operación
  progress.update_spinner(spinner_id, "Finalizando proceso")

  -- Detener el spinner cuando la operación se completa
  vim.defer_fn(function()
    progress.stop_spinner(spinner_id, true)  -- true indica éxito
  end, 1000)
end, 2000)
```

### Barra de progreso

```lua
local progress = require("copilotchatassist.utils.progress")

-- Mostrar una barra de progreso
progress.show_progress_bar("Descargando archivos", 0, {
  width = 40
})

-- Simular actualización de progreso
for i = 1, 10 do
  vim.defer_fn(function()
    progress.show_progress_bar("Descargando archivos", i * 10)
  end, i * 500)
end

-- Cerrar la barra de progreso cuando finalice
vim.defer_fn(function()
  progress.close_progress_bar()
end, 6000)
```

## Implementación Técnica

El sistema utiliza timers de Neovim (vim.loop) para animar los spinners y un namespace dedicado para gestionar la visualización. Los indicadores pueden mostrarse en diferentes ubicaciones:

- **statusline**: Muestra indicadores en la línea de estado de Neovim
- **window**: Crea ventanas flotantes dedicadas para los indicadores

## Consideraciones de Rendimiento

- Los indicadores de progreso están diseñados para tener un impacto mínimo en el rendimiento
- En sistemas con recursos limitados, se puede desactivar el sistema con `use_progress_indicator = false`
- Las operaciones críticas continuarán funcionando incluso si el sistema de progreso falla

## Compatibilidad

- El sistema es compatible con Neovim 0.8.0+
- En terminales sin soporte para caracteres Unicode, los spinners pueden no mostrarse correctamente