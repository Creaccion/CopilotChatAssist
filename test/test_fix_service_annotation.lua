-- Test para validar la corrección del problema con anotaciones @Service en Java
-- Este archivo verifica que la documentación se inserte correctamente antes de @Service

local mock = {}

-- Mock de vim.api
mock.vim = {
  api = {
    nvim_buf_get_lines = function(buffer, start, end_line, strict)
      if buffer == 1 then
        return mock.buffer_content[start + 1] and mock.buffer_content:sub(start + 1, end_line) or {}
      end
      return {}
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
    end
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
  }
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
package.loaded["copilotchatassist.documentation.detector"] = {
  _get_language_handler = function()
    return require("copilotchatassist.documentation.language.java")
  end,
  ISSUE_TYPES = {
    MISSING = "missing",
    OUTDATED = "outdated",
    INCOMPLETE = "incomplete"
  }
}

-- Cargar el módulo Java corregido
local ok, java_handler
ok, java_handler = pcall(function()
  return require("copilotchatassist.documentation.language.java")
end)

if not ok then
  print("ERROR: No se pudo cargar el manejador de Java")
  print("Ruta de búsqueda actual: " .. package.path)
  os.exit(1)
end

-- Configurar el buffer con un ejemplo exacto del problema reportado
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

-- Limpiar estado
mock.modified_content = nil
mock.notifications = {}
mock.log_messages = {}

print("\n=== PRUEBA DE LA CORRECCIÓN CON ANOTACIÓN @Service EN JAVA ===\n")

-- JavaDoc que se va a aplicar
local doc_block = [[/**
 * Mapper service for converting {@link ScheduleOverrideShiftEntity} entities to {@link OverrideShift} domain models.
 * <p>
 * This class provides methods to map persistence entities representing schedule override shifts into
 * domain objects used within the flexible schedules module.
 */]]

-- Aplicar documentación a la clase
print("\nAplicando documentación a la clase...")
local result = java_handler.apply_documentation(1, 10, doc_block)

-- Verificar resultados
print("\nResultado de aplicación: " .. tostring(result))

if mock.modified_content then
  print("\nContenido modificado:")
  print("Desde línea: " .. mock.modified_content.start + 1)
  print("Hasta línea: " .. mock.modified_content.end_line)

  -- Verificar que la documentación se insertó antes de la anotación @Service
  local inserted_before_annotation = mock.modified_content.start <= 9

  if inserted_before_annotation then
    print("\n✅ TEST PASADO: La documentación se insertó correctamente antes de la anotación @Service (línea " .. mock.modified_content.start + 1 .. ")")
  else
    print("\n❌ TEST FALLIDO: La documentación se insertó después de la anotación @Service (línea " .. mock.modified_content.start + 1 .. ")")
  end

  -- Mostrar las primeras líneas insertadas
  print("\nPrimeras líneas de documentación insertada:")
  for i=1, math.min(3, #mock.modified_content.lines) do
    print(i .. ": " .. mock.modified_content.lines[i])
  end
  print("...")
else
  print("\n❌ TEST FALLIDO: No se modificó el buffer")
end

-- Función para construir un resultado combinado
local function get_combined_content()
  if not mock.modified_content then
    return mock.buffer_content
  end

  local result = {}
  local insert_pos = mock.modified_content.start

  -- Copiar líneas antes de la inserción
  for i = 1, insert_pos do
    table.insert(result, mock.buffer_content[i])
  end

  -- Insertar nuevas líneas
  for _, line in ipairs(mock.modified_content.lines) do
    table.insert(result, line)
  end

  -- Copiar líneas después de la inserción
  for i = insert_pos + 1, #mock.buffer_content do
    table.insert(result, mock.buffer_content[i])
  end

  return result
end

-- Mostrar una vista previa del resultado final
local final_content = get_combined_content()
print("\nVista previa del resultado final (primeras 15 líneas):")
for i = 1, math.min(15, #final_content) do
  print(i .. ": " .. final_content[i])
end

print("\n=== FIN DE LA PRUEBA ===")

-- Devolver código de salida según el resultado
if result and mock.modified_content and mock.modified_content.start <= 9 then
  print("\nLa prueba ha pasado exitosamente.")
  os.exit(0)
else
  print("\nLa prueba ha fallado.")
  os.exit(1)
end