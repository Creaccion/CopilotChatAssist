-- Test para verificar el formato correcto de la documentación generada
-- Este script detecta problemas comunes de formato en la documentación

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

      -- Reconstruir el contenido del buffer con las nuevas líneas
      local new_content = {}
      -- Copiar líneas antes del cambio
      for i = 1, start do
        table.insert(new_content, mock.buffer_content[i])
      end
      -- Insertar las nuevas líneas
      for _, line in ipairs(lines) do
        table.insert(new_content, line)
      end
      -- Copiar líneas después del cambio
      for i = end_line + 1, #mock.buffer_content do
        table.insert(new_content, mock.buffer_content[i])
      end
      -- Actualizar el buffer
      mock.buffer_content = new_content
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

local detector = {
  _get_language_handler = function(filetype)
    if filetype == "java" then
      return require("copilotchatassist.documentation.language.java")
    else
      return require("copilotchatassist.documentation.language.elixir")
    end
  end,
  ISSUE_TYPES = {
    MISSING = "missing",
    OUTDATED = "outdated",
    INCOMPLETE = "incomplete"
  }
}
package.loaded["copilotchatassist.documentation.detector"] = detector

-- Mock para common
local common = {
  find_doc_block = function() return nil end,
  is_documentation_outdated = function() return false end,
  is_documentation_incomplete = function() return false end,
  normalize_documentation = function(doc) return doc end
}
package.loaded["copilotchatassist.documentation.language.common"] = common

-- Función para imprimir cabecera
local function print_header(text)
  print("\n" .. string.rep("=", 70))
  print("= " .. text)
  print(string.rep("=", 70))
end

-- Función para verificar si hay documentación duplicada en Java
local function check_java_duplicate_documentation()
  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Establecer tipo de archivo
  vim.bo[1].filetype = "java"

  -- Configurar el buffer con el ejemplo problemático
  mock.buffer_content = {
    "package com.pagerduty.shiftmanagement.flexibleschedules.shared.services;",
    "",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.entities.ScheduleOverrideShiftEntity;",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.models.members.Member;",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.models.shifts.OverrideShift;",
    "import java.util.Map;",
    "import java.util.UUID;",
    "import org.springframework.stereotype.Service;",
    "/**",
    " * Service responsible for mapping {@link ScheduleOverrideShiftEntity} objects to {@link OverrideShift} domain models.",
    " * <p>",
    " * This mapper resolves overridden and overriding members using a provided map of members.",
    " */",
    "    /**",
    "     * Maps a {@link ScheduleOverrideShiftEntity} to an {@link OverrideShift} domain object.",
    "     *",
    "     * @param entity  the {@link ScheduleOverrideShiftEntity} to map",
    "     * @param members a map of {@link UUID} to {@link Member}, used to resolve overridden and overriding members",
    "     * @return the mapped {@link OverrideShift} domain object",
    "     * @throws NullPointerException if {@code entity} or {@code members} is null, or if the overriding member is not found in the map",
    "     */",
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

  -- Cargar el manejador Java
  local ok, java_handler
  ok, java_handler = pcall(function()
    return require("copilotchatassist.documentation.language.java")
  end)

  if not ok then
    print("ERROR: No se pudo cargar el manejador de Java")
    return false
  end

  -- Verificar si hay documentación JavaDoc en múltiples lugares
  local javadoc_positions = {}
  for i, line in ipairs(mock.buffer_content) do
    if line:match("^%s*/%*%*") then
      table.insert(javadoc_positions, i)
    end
  end

  -- Reportar los resultados
  if #javadoc_positions > 1 then
    print("❌ PROBLEMA DETECTADO: Documentación JavaDoc duplicada encontrada en líneas:")
    for _, pos in ipairs(javadoc_positions) do
      print("  - Línea " .. pos)
    end

    -- Verificar si hay un JavaDoc flotante (no inmediatamente antes de clase/método)
    for i, pos in ipairs(javadoc_positions) do
      local end_pos = pos
      while end_pos <= #mock.buffer_content and not mock.buffer_content[end_pos]:match("%*/") do
        end_pos = end_pos + 1
      end

      -- Buscar hasta 3 líneas después del fin del JavaDoc
      local found_code = false
      for j = end_pos + 1, math.min(end_pos + 3, #mock.buffer_content) do
        if mock.buffer_content[j]:match("^%s*public%s+") or
           mock.buffer_content[j]:match("^%s*class%s+") or
           mock.buffer_content[j]:match("^%s*interface%s+") or
           mock.buffer_content[j]:match("^%s*enum%s+") or
           mock.buffer_content[j]:match("^%s*record%s+") or
           mock.buffer_content[j]:match("^%s*void%s+") or
           mock.buffer_content[j]:match("^%s*[%w_.<>]+%s+[%w_]+%(") or
           mock.buffer_content[j]:match("^%s*@") then
          found_code = true
          break
        end
      end

      if not found_code then
        print("  - El JavaDoc en línea " .. pos .. " parece estar flotando sin asociación con código")
      end
    end

    return false
  else
    print("✅ No se detectó documentación JavaDoc duplicada")
    return true
  end
end

-- Función para verificar el posicionamiento correcto en Java
local function check_java_documentation_positioning()
  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Establecer tipo de archivo
  vim.bo[1].filetype = "java"

  -- Configurar el buffer con el ejemplo problemático
  mock.buffer_content = {
    "package com.example.service;",
    "",
    "import org.springframework.stereotype.Service;",
    "",
    "@Service",
    "public class ExampleService {",
    "",
    "  public void doSomething() {",
    "    // Implementation",
    "  }",
    "}"
  }

  -- Cargar el manejador Java
  local ok, java_handler
  ok, java_handler = pcall(function()
    return require("copilotchatassist.documentation.language.java")
  end)

  if not ok then
    print("ERROR: No se pudo cargar el manejador de Java")
    return false
  end

  -- Aplicar documentación
  local doc_block = [[/**
 * Example service for demonstration purposes.
 */]]

  -- Aplicar a la clase (línea 5 donde está @Service)
  local result = java_handler.apply_documentation(1, 5, doc_block)

  if not result or not mock.modified_content then
    print("❌ Falló la aplicación de documentación")
    return false
  end

  -- Verificar la posición correcta (antes de @Service)
  local correct_position = mock.modified_content.start < 5
  if not correct_position then
    print("❌ La documentación no se insertó correctamente antes de la anotación @Service")
    print("  Posición de inserción: línea " .. (mock.modified_content.start + 1))
    return false
  else
    print("✅ La documentación se posicionó correctamente antes de la anotación @Service")
    return true
  end
end

-- Función para verificar el formato de documentación en Elixir
local function check_elixir_documentation_format()
  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Establecer tipo de archivo
  vim.bo[1].filetype = "elixir"

  -- Configurar el buffer con el ejemplo problemático
  mock.buffer_content = {
    "@doc \"\"\"",
    "# Functions",
    "  * `handle_create_request/2` - Handles POST requests to create custom shifts for a given schedule.",
    "# Parameters",
    "# Returns",
    "# Errors",
    "\"\"\"",
    "defmodule IrSchedulesFacadeWeb.CustomShiftsController do",
    "  use IrSchedulesFacadeWeb, :controller",
    "",
    "  require Logger",
    "",
    "  alias IrSchedulesFacade.Clients.ShiftManagementService.SmsHeaders",
    "  alias IrSchedulesFacade.Clients.Web.WebHeaders",
    "",
    "  alias IrSchedulesFacadeWeb.ErrorResponse",
    "  alias IrSchedulesFacadeWeb.Services.FlexibleSchedules.CustomShiftsService",
    "  alias IrSchedulesFacadeWeb.Validation.CustomShiftValidator",
    "",
    "  action_fallback(IrSchedulesFacadeWeb.FlexibleSchedulesFallbackController)",
    "",
    "  @spec handle_create_request(Plug.Conn.t(), map()) :: Plug.Conn.t()",
    "  @doc \"\"\"",
    "  # Parameters",
    "  # Returns",
    "  # Errors",
    "  \"\"\"",
    "",
    "  def handle_create_request(conn, %{\"schedules_id\" => schedule_id}) do",
    "    Logger.metadata(schedule_id: IdUtils.maybe_deobfuscate(schedule_id))",
    "    Logger.info(\"POST custom shifts request received\")",
    "",
    "    %{auth_data: %{user_id: user_id}} = conn.assigns",
    "    web_headers = WebHeaders.from_conn(conn)",
    "    sms_headers = SmsHeaders.from_conn(conn)",
    "",
    "    with {:ok, _validated_params} <-",
    "           CustomShiftValidator.validate_create_custom_shifts_request(conn.body_params),",
    "         {:ok, sms_response} <-",
    "           CustomShiftsService.create_custom_shifts(",
    "             schedule_id,",
    "             conn.body_params,",
    "             user_id,",
    "             sms_headers,",
    "             web_headers",
    "           ) do",
    "      Logger.info(\"Successfully created custom shifts and stored entries in Web\")",
    "      StatsOwl.increment(\"custom_shifts.create.success\")",
    "",
    "      conn",
    "      |> put_status(201)",
    "      |> json(sms_response)",
    "    end",
    "  rescue",
    "    err ->",
    "      ErrorResponse.handle_rescue(conn, err, :custom_shifts_controller, :handle_create_request)",
    "  end",
    "end"
  }

  -- Cargar el manejador Elixir
  local ok, elixir_handler
  ok, elixir_handler = pcall(function()
    return require("copilotchatassist.documentation.language.elixir")
  end)

  if not ok then
    print("ERROR: No se pudo cargar el manejador de Elixir")
    return false
  end

  -- Verificar documentación vacía
  local empty_sections_found = false
  local doc_positions = {}
  local space_after_doc = false
  local doc_outside_module = false

  -- Verificar si hay alguna documentación antes de defmodule
  local module_line = 0
  for i, line in ipairs(mock.buffer_content) do
    if line:match("^defmodule") then
      module_line = i
      break
    end
  end

  for i, line in ipairs(mock.buffer_content) do
    if line:match("^%s*@doc") or line:match("^%s*@moduledoc") then
      table.insert(doc_positions, i)

      -- Verificar si hay un @doc fuera del módulo
      if i < module_line and module_line > 0 and line:match("^%s*@doc") then
        doc_outside_module = true
        print("❌ Documentación @doc encontrada fuera del módulo en línea " .. i)
      end

      -- Verificar espacio después del bloque @doc
      if line:match("^%s*@doc %s*\"\"\"") then
        -- Buscar el cierre del bloque heredoc
        local doc_end = nil
        for j = i + 1, math.min(i + 20, #mock.buffer_content) do
          if mock.buffer_content[j]:match("%s*\"\"\"%s*$") then
            doc_end = j
            break
          end
        end

        -- Verificar si hay un espacio entre el cierre de la documentación y el código
        if doc_end and doc_end + 1 <= #mock.buffer_content and
           mock.buffer_content[doc_end + 1]:match("^%s*$") then
          space_after_doc = true
          print("❌ Espacio innecesario después del bloque @doc en línea " .. doc_end)
        end
      end
    end

    if line:match("^%s*#%s*Parameters%s*$") or
       line:match("^%s*#%s*Returns%s*$") or
       line:match("^%s*#%s*Errors%s*$") then
      -- Verificar si la siguiente línea tiene contenido significativo
      local next_line = mock.buffer_content[i + 1]
      if not next_line or
         next_line:match("^%s*$") or
         next_line:match("^%s*#") or
         next_line:match("^%s*\"\"\"%s*$") then
        empty_sections_found = true
        print("❌ Sección vacía encontrada en línea " .. i .. ": " .. line)
      end
    end
  end

  -- Verificar documentación duplicada
  if #doc_positions > 1 then
    print("❌ Se encontró documentación duplicada en Elixir en líneas:")
    for _, pos in ipairs(doc_positions) do
      print("  - Línea " .. pos .. ": " .. mock.buffer_content[pos])
    end
  end

  if empty_sections_found or #doc_positions > 1 or space_after_doc or doc_outside_module then
    return false
  else
    print("✅ La documentación de Elixir tiene un formato correcto")
    return true
  end
end

-- Ejecutar pruebas
print_header("VERIFICACIÓN DE FORMATO DE DOCUMENTACIÓN")

print_header("1. VERIFICACIÓN DE DUPLICACIÓN DE DOCUMENTACIÓN JAVA")
local java_dup_ok = check_java_duplicate_documentation()

print_header("2. VERIFICACIÓN DE POSICIONAMIENTO DE DOCUMENTACIÓN JAVA")
local java_pos_ok = check_java_documentation_positioning()

print_header("3. VERIFICACIÓN DE FORMATO DE DOCUMENTACIÓN ELIXIR")
local elixir_format_ok = check_elixir_documentation_format()

print_header("RESULTADOS FINALES")

if java_dup_ok and java_pos_ok and elixir_format_ok then
  print("✅ Todas las verificaciones de formato pasaron correctamente")
  os.exit(0)
else
  print("❌ Se encontraron problemas de formato en la documentación:")
  if not java_dup_ok then
    print("  - Documentación Java duplicada o flotante")
  end
  if not java_pos_ok then
    print("  - Posicionamiento incorrecto de documentación Java")
  end
  if not elixir_format_ok then
    print("  - Formato incorrecto o documentación duplicada en Elixir")
  end
  os.exit(1)
end