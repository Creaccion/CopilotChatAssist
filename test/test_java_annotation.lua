-- Test para validar la corrección del problema de detección de anotaciones como elementos principales
-- El problema ocurría cuando la anotación @Service era detectada como elemento en lugar de la clase

local mock = {}

-- Mock de vim.api
mock.vim = {
  api = {
    nvim_buf_get_lines = function(buffer, start, end_line, strict)
      return mock.buffer_content and table.move(mock.buffer_content, start + 1, end_line, 1, {}) or {}
    end,
    nvim_buf_set_lines = function(buffer, start, end_line, strict, lines)
      -- Guardar las líneas modificadas para verificación
      mock.modified_content = {
        buffer = buffer,
        start = start,
        end_line = end_line,
        lines = lines
      }
    end,
    nvim_buf_line_count = function(buffer)
      return #mock.buffer_content
    end,
    nvim_buf_is_valid = function(buffer)
      return buffer == 1
    end,
    nvim_create_augroup = function(name, opts)
      return 1
    end,
    nvim_create_autocmd = function(event, opts)
      -- No hacer nada
    end
  },
  bo = {
    [1] = { filetype = "java" }
  },
  fn = {
    fnamemodify = function(file, mods)
      return file
    end,
    setenv = function() end
  },
  split = function(str, sep)
    local result = {}
    local pattern = string.format("([^%s]+)", sep)
    for match in str:gmatch(pattern) do
      table.insert(result, match)
    end
    return result
  end,
  notify = function(msg, level)
    mock.notifications = mock.notifications or {}
    table.insert(mock.notifications, { msg = msg, level = level })
  end,
  log = {
    levels = {
      ERROR = 1,
      WARN = 2,
      INFO = 3,
      DEBUG = 4
    }
  },
  defer_fn = function(f) f() end
}

-- Mock de log con detalle
local log = {
  debug = function(msg)
    mock.log_messages = mock.log_messages or {}
    table.insert(mock.log_messages, { level = "debug", msg = msg })
    print("[DEBUG] " .. msg)
  end,
  info = function(msg)
    mock.log_messages = mock.log_messages or {}
    table.insert(mock.log_messages, { level = "info", msg = msg })
    print("[INFO] " .. msg)
  end,
  warn = function(msg)
    mock.log_messages = mock.log_messages or {}
    table.insert(mock.log_messages, { level = "warn", msg = msg })
    print("[WARN] " .. msg)
  end,
  error = function(msg)
    mock.log_messages = mock.log_messages or {}
    table.insert(mock.log_messages, { level = "error", msg = msg })
    print("[ERROR] " .. msg)
  end
}

-- Añadir ruta de búsqueda para encontrar los módulos de CopilotChatAssist
local script_path = debug.getinfo(1).source:match("@(.*/)") or ""
script_path = script_path:sub(1, -6)  -- Quitar 'test/'
package.path = script_path .. "lua/?.lua;" .. package.path
package.path = script_path .. "?.lua;" .. package.path

-- Inyectar mocks
_G.vim = mock.vim
package.loaded["copilotchatassist.utils.log"] = log

-- Importar el módulo detector y el módulo de lenguaje Java
local detector = require("copilotchatassist.documentation.detector")
local java_handler = require("copilotchatassist.documentation.language.java")

-- Habilitar el modo de depuración para todos los módulos
_G.vim.g = {}
_G.vim.g.copilotchatassist_debug = true

-- Función para imprimir cabecera
local function print_header(text)
  print("\n" .. string.rep("=", 70))
  print("= " .. text)
  print(string.rep("=", 70))
end

-- Función para imprimir resultado
local function print_result(test_name, success, error_msg)
  if success then
    print("✅ PASS: " .. test_name)
  else
    print("❌ FAIL: " .. test_name .. (error_msg and " - " .. error_msg or ""))
  end
end

-- Configurar el buffer con el ejemplo problemático
function setup_test_buffer()
  mock.buffer_content = {
    "package com.pagerduty.shiftmanagement.flexibleschedules.shared.services;",
    "",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.entities.ScheduleOverrideShiftEntity;",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.models.members.Member;",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.models.shifts.OverrideShift;",
    "import java.util.Map;",
    "import java.util.UUID;",
    "import org.springframework.stereotype.Service;",
    "",
    "@Service",
    "public class OverrideShiftMapper {",
    "",
    "  public OverrideShift toDomain(ScheduleOverrideShiftEntity entity, Map<UUID, Member> members) {",
    "    Member overriddenMember =",
    "        entity.getOverriddenMemberId() != null ? members.get(entity.getOverriddenMemberId()) : null;",
    "    Member overridingMember = members.get(entity.getOverridingMemberId());",
    "",
    "    return OverrideShift.builder()",
    "        .id(entity.getId())",
    "        .overriddenMember(overriddenMember)",
    "        .overridingMember(overridingMember)",
    "        .startTime(entity.getStartTime())",
    "        .endTime(entity.getEndTime())",
    "        .build();",
    "  }",
    "}"
  }
end

-- Prueba para verificar que @Service no sea detectado como elemento documentable
function test_service_annotation_not_detected()
  setup_test_buffer()

  -- Mostrar el contenido del buffer para verificación
  print("\nContenido del buffer de prueba:")
  for i, line in ipairs(mock.buffer_content) do
    print(i .. ": " .. line)
  end

  -- Escanear el buffer utilizando el detector general para depuración
  local items = detector.scan_buffer(1, {include_records = true})

  print("\nElementos detectados por el detector general:")
  for i, item in ipairs(items) do
    print("- Elemento " .. i .. ": " .. item.name .. " (" .. item.type .. ") en línea " .. item.start_line)
  end

  -- Escanear el buffer con el manejador de Java directamente
  local java_items = java_handler.scan_buffer(1)

  print("\nElementos detectados por el manejador Java:")
  for i, item in ipairs(java_items) do
    print("- Elemento " .. i .. ": " .. item.name .. " (" .. item.type .. ") en línea " .. item.start_line)
  end

  -- Verificar resultados
  local service_found = false
  local class_found = false
  local method_found = false

  for _, item in ipairs(java_items) do
    if item.type == "annotation" and item.name == "Service" then
      service_found = true
    end
    if item.type == "class" and item.name == "OverrideShiftMapper" then
      class_found = true
    end
    if item.type == "method" and item.name == "toDomain" then
      method_found = true
    end
  end

  -- No debería encontrar la anotación @Service como elemento documentable
  if service_found then
    print("❌ ERROR: Se encontró la anotación @Service como elemento documentable")
    return false
  else
    print("✅ OK: La anotación @Service NO fue detectada como elemento documentable")
  end

  -- Debería encontrar la clase y el método
  if not class_found then
    print("❌ ERROR: No se encontró la clase OverrideShiftMapper")
    return false
  else
    print("✅ OK: Clase OverrideShiftMapper detectada correctamente")
  end

  if not method_found then
    print("❌ ERROR: No se encontró el método toDomain")
    return false
  else
    print("✅ OK: Método toDomain detectado correctamente")
  end

  return true
end

-- Ejecutar prueba
print_header("PRUEBA DE DETECCIÓN DE ANOTACIONES EN JAVA")

local success = test_service_annotation_not_detected()

print_header("RESULTADOS FINALES")
if success then
  print("✅ TODAS LAS PRUEBAS PASARON")
else
  print("❌ UNA O MÁS PRUEBAS FALLARON")
end

return success