-- Prompt for global project context analysis
local options = require("copilotchatassist.options")

local M = {}

M.default = [[
Siempre usando el lenguage ]] .. options.language .. [[ para nuestra interaccion, y el lenguaje ]] .. options.code_language .. [[ para todo lo relacionado al código, documentacion, debugs. 
Analiza el proyecto detectando automáticamente el stack tecnológico principal según los archivos presentes: ##files://glob/**.*

- Si detectas más de un stack, pregunta cuál debe usarse.
- Incluye patrones de archivos relevantes, archivos de infraestructura y contenedores si existen.
- Analiza todos los archivos de documentación Markdown (*.md) ##files://glob/**.md y utiliza su contenido para enriquecer el contexto y el análisis.
- Si necesitas más información, solicita la estructura del proyecto o acceso a archivos específicos.

Proporciona:
- Resumen del propósito del proyecto
- Estructura general y organización de componentes
- Áreas de mejora en arquitectura, código y buenas prácticas
- Análisis de dependencias y recomendaciones
- Sugerencias para documentación y contexto
- Recomendaciones de CI/CD (por ejemplo: Buildkite, CircleCI)
- Mejores prácticas de seguridad y rendimiento
- Otros aspectos relevantes

Mantén este contexto para futuras consultas.
Importante, este resultado no interactuará con el usuario, por lo que no solicites preguntas, en su lugar agrega puntos en el resultado
para ser tratados con el usuario cuando sea el momento.
]]

return M

