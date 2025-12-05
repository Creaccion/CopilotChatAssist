-- Test para validar la corrección del problema de detección de módulos Elixir
-- Este archivo verifica que se detecten correctamente los controladores Elixir

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
    [1] = { filetype = "elixir" }
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
    return require("copilotchatassist.documentation.language.elixir")
  end,
  ISSUE_TYPES = {
    MISSING = "missing",
    OUTDATED = "outdated",
    INCOMPLETE = "incomplete"
  }
}

-- Cargar el módulo Elixir corregido
local ok, elixir_handler
ok, elixir_handler = pcall(function()
  return require("copilotchatassist.documentation.language.elixir")
end)

if not ok then
  print("ERROR: No se pudo cargar el manejador de Elixir")
  print("Ruta de búsqueda actual: " .. package.path)
  os.exit(1)
end

-- Configurar el buffer con un ejemplo exacto del problema reportado
mock.buffer_content = {
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

-- Limpiar estado
mock.modified_content = nil
mock.notifications = {}
mock.log_messages = {}

print("\n=== PRUEBA DE LA CORRECCIÓN DE DETECCIÓN DE MÓDULOS ELIXIR ===\n")

-- Configurar para Elixir
elixir_handler.setup_for_elixir(1)

-- Escanear el buffer en busca de elementos para documentar
print("Escaneando buffer en busca de elementos para documentar...")
local items = elixir_handler.scan_buffer(1)

-- Verificar resultados
print("\nElementos detectados: " .. #items)

-- Detalles de los elementos encontrados
if #items > 0 then
  print("\nDetalles de los elementos encontrados:")
  for i, item in ipairs(items) do
    print("Elemento " .. i .. ": " .. item.name .. " (" .. item.type .. ") - " .. item.issue_type)
    print("  Línea de inicio: " .. item.start_line)
    print("  Línea de fin: " .. item.end_line)
  end

  -- Verificar si se detectó el módulo correcto
  local module_found = false
  for _, item in ipairs(items) do
    if item.type == "module" and item.name == "IrSchedulesFacadeWeb.CustomShiftsController" then
      module_found = true
      break
    end
  end

  if module_found then
    print("\n✅ TEST PASADO: Se detectó correctamente el módulo IrSchedulesFacadeWeb.CustomShiftsController")
  else
    print("\n❌ TEST FALLIDO: No se detectó el módulo IrSchedulesFacadeWeb.CustomShiftsController")
    for _, item in ipairs(items) do
      if item.type == "module" then
        print("  Módulo detectado incorrectamente: " .. item.name)
      end
    end
  end
else
  print("\n❌ TEST FALLIDO: No se detectó ningún elemento para documentar")
end

-- Probar aplicación de documentación al módulo
print("\nAplicando documentación al módulo...")

local module_doc = "@moduledoc \"\"\"\nControlador para gestionar turnos personalizados en la interfaz web de la fachada de programación.\n\nEste módulo proporciona endpoints para crear y gestionar turnos personalizados,\ninteractuando con el servicio de gestión de turnos subyacente.\n\"\"\""

local result = elixir_handler.apply_documentation(1, 1, module_doc)

print("\nResultado de aplicación: " .. tostring(result))

if mock.modified_content then
  print("\nDocumentación aplicada correctamente.")
  print("Línea de inicio: " .. mock.modified_content.start + 1)

  -- Mostrar las primeras líneas insertadas
  print("\nPrimeras líneas de documentación insertada:")
  for i=1, math.min(3, #mock.modified_content.lines) do
    print(i .. ": " .. mock.modified_content.lines[i])
  end
  print("...")
else
  print("\n❌ No se modificó el buffer")
end

print("\n=== FIN DE LA PRUEBA ===")

-- Devolver código de salida según el resultado
local module_detected = false
for _, item in ipairs(items) do
  if item.type == "module" and item.name == "IrSchedulesFacadeWeb.CustomShiftsController" then
    module_detected = true
    break
  end
end

if module_detected then
  print("\nLa prueba ha pasado exitosamente.")
  os.exit(0)
else
  print("\nLa prueba ha fallado.")
  os.exit(1)
end