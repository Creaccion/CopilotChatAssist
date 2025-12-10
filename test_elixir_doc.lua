-- Script para probar la funcionalidad de documentación de Elixir
-- Este script simula el proceso de documentar un archivo Elixir con
-- diferentes casos de uso, enfocándose en los problemas de inserción
-- que fueron corregidos

local log = {}
function log.debug(msg) print("[DEBUG] " .. msg) end
function log.info(msg) print("[INFO] " .. msg) end
function log.warn(msg) print("[WARN] " .. msg) end
function log.error(msg) print("[ERROR] " .. msg) end

-- Mock de vim.api
local vim = {
  api = {
    nvim_buf_get_lines = function(_, start, _end, _)
      local lines = {
        "defmodule TestModule do",
        "  @moduledoc \"\"\"",
        "  Este es un módulo de prueba para documentación",
        "  \"\"\"",
        "",
        "  def function_one(arg1, arg2) do",
        "    # Implementación",
        "    arg1 + arg2",
        "  end",
        "",
        "  def function_two(name, %{id: id}) when is_binary(name) do",
        "    # Otra implementación",
        "    {name, id}",
        "  end",
        "end"
      }
      return vim.list_slice(lines, start + 1, _end)
    end,
    nvim_buf_set_lines = function(_, start, _end, _, new_lines)
      print("\n===== INSERCIÓN DE LÍNEAS =====")
      print("Desde línea: " .. start)
      print("Hasta línea: " .. _end)
      print("Nuevas líneas:")
      for i, line in ipairs(new_lines) do
        print(i .. ": " .. line)
      end
      print("============================\n")
    end,
    nvim_buf_line_count = function(_)
      return 15  -- Longitud simulada del buffer
    end,
    nvim_buf_is_valid = function(_)
      return true
    end,
    nvim_create_augroup = function(_, _)
      return 1
    end,
    nvim_create_autocmd = function(_, _)
      -- Nada
    end
  },
  bo = {
    [1] = { filetype = "elixir" }
  },
  defer_fn = function(fn, _)
    fn()
  end,
  list_slice = function(list, start, _end)
    local result = {}
    for i = start, _end do
      table.insert(result, list[i])
    end
    return result
  end,
  split = function(str, sep)
    local result = {}
    local pattern = string.format("([^%s]+)", sep)
    for match in str:gmatch(pattern) do
      table.insert(result, match)
    end
    return result
  end,
  notify = function(msg, level)
    level = level or 2  -- INFO por defecto
    local levels = {"ERROR", "WARN", "INFO", "DEBUG"}
    print("[NOTIFY:" .. levels[level] .. "] " .. msg)
  end,
  fn = {
    setenv = function(_, _)
      -- Nada
    end
  },
  log = {
    levels = {
      ERROR = 1,
      WARN = 2,
      INFO = 3,
      DEBUG = 4
    }
  }
}
_G.vim = vim

-- Cargar el módulo de documentación (simulación)
print("\n=== CARGANDO MÓDULOS DE DOCUMENTACIÓN (SIMULADO) ===\n")
package.loaded["copilotchatassist.utils.log"] = log

-- Simular el detector de documentación
local detector = {
  ISSUE_TYPES = {
    MISSING = "missing",
    OUTDATED = "outdated",
    INCOMPLETE = "incomplete"
  },
  _get_language_handler = function(filetype)
    print("[MOCK] Obteniendo manejador para: " .. filetype)
    -- Devolvemos el manejador real de elixir
    return require("copilotchatassist.documentation.language.elixir")
  end
}
package.loaded["copilotchatassist.documentation.detector"] = detector

-- Simular el módulo de utilidades
local utils = {
  get_function_context = function(_, _, _)
    return "# Contexto simulado\ndef other_function() do\n  :ok\nend"
  end,
  extract_documentation_from_response = function(response)
    print("[MOCK] Extrayendo documentación de respuesta")
    return response
  end,
  validate_documentation = function(_, _)
    return true
  end
}
package.loaded["copilotchatassist.documentation.utils"] = utils

-- Cargar el manejador de Elixir
local elixir_handler = require("copilotchatassist.documentation.language.elixir")

-- Prueba 1: Configuración para Elixir
print("\n=== PRUEBA 1: CONFIGURACIÓN PARA ELIXIR ===\n")
elixir_handler.setup_for_elixir(1)

-- Prueba 2: Detección de módulo al inicio
print("\n=== PRUEBA 2: DETECCIÓN DE MÓDULO AL INICIO ===\n")
local items = elixir_handler.scan_buffer(1)
for i, item in ipairs(items) do
  print(string.format("Elemento %d: %s (%s) - %s", i, item.name, item.type, item.issue_type))
end

-- Prueba 3: Aplicar documentación al inicio del archivo
print("\n=== PRUEBA 3: APLICAR DOCUMENTACIÓN AL INICIO DEL ARCHIVO ===\n")
local module_doc = "@moduledoc \"\"\"\nEste es un módulo de prueba con documentación actualizada\nque se inserta al inicio del archivo.\n\nTiene múltiples líneas para probar el formato.\n\"\"\""
local result = elixir_handler.apply_documentation(1, 1, module_doc)
print("Resultado:", result)

-- Prueba 4: Actualizar documentación existente de módulo
print("\n=== PRUEBA 4: ACTUALIZAR DOCUMENTACIÓN EXISTENTE DE MÓDULO ===\n")
local updated_doc = "@moduledoc \"\"\"\nDocumentación actualizada para el módulo de prueba.\nVerificando que el manejo especial para módulos Elixir\nfunciona correctamente.\n\"\"\""
local update_result = elixir_handler.update_documentation(1, 2, 4, updated_doc)
print("Resultado de actualización:", update_result)

-- Prueba 5: Aplicar documentación a una función
print("\n=== PRUEBA 5: APLICAR DOCUMENTACIÓN A UNA FUNCIÓN ===\n")
local function_doc = "@doc \"\"\"\nDocumenta una función que suma dos argumentos.\n\n## Parámetros\n\n- arg1: Primer argumento\n- arg2: Segundo argumento\n\n## Retorno\n\nLa suma de arg1 y arg2\n\"\"\""
local func_result = elixir_handler.apply_documentation(1, 6, function_doc)
print("Resultado:", func_result)

print("\n=== PRUEBAS COMPLETADAS ===\n")
print("Verificación de la corrección del error de inserción de documentación en archivos Elixir")
print("y la implementación del manejo especial para módulos Elixir.")