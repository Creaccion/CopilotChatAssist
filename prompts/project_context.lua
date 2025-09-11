-- Prompt for initial project context analysis

local M = {}

M.default = [[
Analiza el proyecto detectando automáticamente el stack tecnológico principal según los archivos presentes: ##files://glob/**.*

- Si detectas más de un stack, pregunta cuál debe usarse.
- Incluye patrones de archivos relevantes, archivos de infraestructura y contenedores si existen.
- Considera los cambios en el branch actual: ##git://diff/main..HEAD.
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
Responde exclusivamente en español a menos que el usuario pida explícitamente otro idioma.
]]

return M
