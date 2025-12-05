-- Módulo de prueba para el sistema de logs
local M = {}
local options = require("copilotchatassist.options")
local log = require("copilotchatassist.utils.log")

-- Función para probar diferentes configuraciones de nivel de log
function M.test_log_levels()
  print("=== PRUEBA DE NIVELES DE LOG ===")

  -- Obtener configuración actual para restaurarla después
  local current_level = options.get().log_level

  -- Probar con diferentes tipos de valores para log_level
  local test_levels = {
    -- Valores numéricos
    vim.log.levels.ERROR,
    vim.log.levels.WARN,
    vim.log.levels.INFO,
    vim.log.levels.DEBUG,
    vim.log.levels.TRACE,

    -- Valores string
    "ERROR",
    "WARN",
    "INFO",
    "DEBUG",
    "TRACE",

    -- Valores inválidos (deberían usar INFO por defecto)
    nil,
    "",
    "INVALID_LEVEL",
    {},
    0,  -- aunque es un número válido para ERROR, comprobamos que funciona
  }

  for _, level in ipairs(test_levels) do
    -- Configurar el nivel
    options.set({ log_level = level })

    -- Mostrar qué nivel estamos probando
    print("Probando nivel: " .. tostring(level) .. " (tipo: " .. type(level) .. ")")

    -- Obtener configuración resultante
    local config = log.get_current_config()
    print("  Nivel resultante: " .. config.level_name .. " (" .. config.level .. ")")

    -- Probar cada tipo de mensaje
    print("  Mensaje ERROR:")
    log.error("Esto es un ERROR de prueba")

    print("  Mensaje WARN:")
    log.warn("Esto es un WARN de prueba")

    print("  Mensaje INFO:")
    log.info("Esto es un INFO de prueba")

    print("  Mensaje DEBUG:")
    log.debug("Esto es un DEBUG de prueba")

    print("  Mensaje TRACE:")
    log.trace("Esto es un TRACE de prueba")

    print("---")
  end

  -- Restaurar configuración original
  options.set({ log_level = current_level })
  print("Nivel de log restaurado a: " .. tostring(current_level))
end

-- Ejecutar pruebas automáticamente al cargar el módulo
M.test_log_levels()

return M