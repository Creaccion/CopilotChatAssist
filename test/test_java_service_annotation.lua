-- Test para el problema específico con anotaciones @Service en Java
-- Este archivo se centra en el problema de documentación duplicada con la anotación @Service

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

print("\n=== PRUEBA DEL PROBLEMA CON ANOTACIÓN @Service EN JAVA ===\n")
print("Estado del archivo antes de aplicar documentación:")
for i, line in ipairs(mock.buffer_content) do
  print(i .. ": " .. line)
end

-- Cargar el módulo de Java
local java_handler = require("copilotchatassist.documentation.language.java")

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
  print("Nuevas líneas:")
  for i, line in ipairs(mock.modified_content.lines) do
    print(i .. ": " .. line)
  end

  -- Verificar que la documentación se insertó antes de la anotación @Service
  local inserted_before_annotation = mock.modified_content.start <= 9
  print("\nLa documentación se insertó " ..
    (inserted_before_annotation and "CORRECTAMENTE antes de @Service" or "INCORRECTAMENTE después de @Service"))

  if inserted_before_annotation then
    print("\n✅ TEST PASADO: La documentación se insertó correctamente antes de la anotación @Service")
  else
    print("\n❌ TEST FALLIDO: La documentación se insertó después de la anotación @Service")
  end
else
  print("\n❌ TEST FALLIDO: No se modificó el buffer")
end

-- Mostrar cómo quedaría el archivo después de la modificación
local new_content = {}
local doc_line_count = mock.modified_content and #mock.modified_content.lines or 0
local insertion_point = mock.modified_content and mock.modified_content.start or 0

for i = 1, insertion_point do
  table.insert(new_content, mock.buffer_content[i])
end

if mock.modified_content then
  for _, line in ipairs(mock.modified_content.lines) do
    table.insert(new_content, line)
  end
end

for i = insertion_point + 1, #mock.buffer_content do
  table.insert(new_content, mock.buffer_content[i])
end

print("\nEstado final del archivo después de la modificación:")
for i, line in ipairs(new_content) do
  print(i .. ": " .. line)
end