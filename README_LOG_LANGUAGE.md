# Log y Configuración de Idioma en CopilotChatAssist

Este documento describe cómo configurar y usar las opciones de log y las configuraciones de idioma en CopilotChatAssist.

## Configuración de Logs

CopilotChatAssist ahora soporta configuración de niveles de log, que te permite controlar la cantidad de información de depuración que se muestra.

### Niveles de Log Disponibles

Los niveles de log, ordenados de menor a mayor verbosidad:

1. **ERROR** (0): Solo muestra errores graves
2. **WARN** (1): Muestra advertencias y errores
3. **INFO** (2): Muestra información general, advertencias y errores
4. **DEBUG** (3): Muestra información detallada para depuración
5. **TRACE** (4): Muestra información extremadamente detallada

### Configuración

Puedes configurar el nivel de log de varias formas:

#### En tu configuración de Neovim

En tu archivo `copilot-files.lua` o equivalente:

```lua
require("copilotchatassist").setup({
  log_level = vim.log.levels.INFO,  -- O cualquier otro nivel
})
```

#### Durante la sesión

Usando el comando `:CopilotChatLogLevel`:

```vim
:CopilotChatLogLevel INFO    " Establece el nivel a INFO
:CopilotChatLogLevel DEBUG   " Establece el nivel a DEBUG
:CopilotChatLogLevel         " Muestra el nivel actual y qué niveles están activos
```

### Ver Logs de Depuración

Usa el comando `:CopilotChatDebugLogs` para ver los logs de depuración actuales.

## Configuración de Idioma

CopilotChatAssist ahora soporta múltiples idiomas para la interfaz de usuario y la documentación generada.

### Idiomas Disponibles

- **english**: Inglés
- **spanish**: Español

### Configuración

Puedes configurar el idioma de varias formas:

#### En tu configuración de Neovim

En tu archivo `copilot-files.lua` o equivalente:

```lua
require("copilotchatassist").setup({
  language = "spanish",        -- Idioma para la interfaz de usuario
  code_language = "english",   -- Idioma para la documentación de código
})
```

#### Durante la sesión

Usando el comando `:CopilotChatLanguage`:

```vim
:CopilotChatLanguage spanish   " Establece el idioma a español
:CopilotChatLanguage english   " Establece el idioma a inglés
:CopilotChatLanguage           " Muestra el idioma actual
```

### Idiomas Separados para UI y Código

Puedes tener un idioma diferente para la interfaz de usuario y otro para el código:

- **language**: Controla la interfaz de usuario, mensajes y menús
- **code_language**: Controla el idioma de la documentación generada para el código

Esto permite, por ejemplo, tener la interfaz en español pero generar documentación de código en inglés.

## Funcionalidad de Internacionalización (i18n)

El módulo `i18n.lua` proporciona funcionalidades para:

1. Traducir cadenas de texto según el idioma configurado
2. Detectar automáticamente el idioma de un texto
3. Traducir contenido entre idiomas
4. Actualizar texto existente cuando cambia el idioma

### Uso en el Código

Para desarrolladores que extienden CopilotChatAssist, pueden usar:

```lua
local i18n = require("copilotchatassist.i18n")

-- Obtener texto traducido
local texto = i18n.t("menu.select_elements")

-- Texto formateado con variables
local msg = i18n.t("documentation.elements_found", {count})

-- Traducir texto existente a otro idioma
local translated = i18n.translate_text(text, "english")

-- Obtener idioma configurado
local lang = i18n.get_current_language()
```

## Actualizando Descripciones Existentes

Cuando cambias el idioma, puedes actualizar descripciones existentes (como en PRs) llamando a la función correspondiente:

```vim
:CopilotChatLanguage english
```

El plugin detectará si hay descripciones existentes y preguntará si deseas traducirlas al nuevo idioma.