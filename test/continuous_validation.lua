-- Script persistente para validación continua de funcionalidades corregidas
-- Este script ejecuta un conjunto de pruebas específicas para verificar que
-- las mejoras implementadas siguen funcionando correctamente.

local mock = {}
local tests = {}
local failures = {}
local successes = 0

-- Configuración para imprimir resultados de manera clara
local function print_header(text)
  print("\n" .. string.rep("=", 80))
  print("= " .. text)
  print(string.rep("=", 80))
end

local function print_subheader(text)
  print("\n" .. string.rep("-", 60))
  print("-- " .. text)
  print(string.rep("-", 60))
end

local function print_result(test_name, success, message)
  if success then
    print("✅ " .. test_name .. ": PASADO")
    successes = successes + 1
  else
    print("❌ " .. test_name .. ": FALLIDO - " .. (message or "Error desconocido"))
    table.insert(failures, {name = test_name, message = message or "Error desconocido"})
  end
end

-- Función para configurar el entorno de pruebas
local function setup_test_env()
  -- Añadir ruta de búsqueda para encontrar los módulos
  local script_path = debug.getinfo(1).source:match("@(.*/)")
  if script_path then
    script_path = script_path:sub(1, -6)  -- Quitar 'test/'
    package.path = script_path .. "lua/?.lua;" .. package.path
    package.path = script_path .. "?.lua;" .. package.path
  end

  -- Mock para vim
  mock.vim = {
    api = {
      nvim_buf_get_lines = function(buffer, start, end_line, strict)
        return mock.buffer_content and table.move(mock.buffer_content, start + 1, end_line, 1, {}) or {}
      end,
      nvim_buf_set_lines = function(buffer, start, end_line, strict, lines)
        mock.modified_content = {
          buffer = buffer,
          start = start,
          end_line = end_line,
          lines = lines
        }
      end,
      nvim_buf_line_count = function(buffer)
        return mock.buffer_content and #mock.buffer_content or 0
      end,
      nvim_buf_is_valid = function(buffer)
        return buffer == 1
      end,
      nvim_create_augroup = function() return 1 end,
      nvim_create_autocmd = function() end
    },
    bo = {
      [1] = { filetype = "java" } -- Se cambiará según la prueba
    },
    fn = {
      fnamemodify = function(file, mods) return file end,
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

  -- Mock para log
  local log = {
    debug = function(msg)
      mock.log_messages = mock.log_messages or {}
      table.insert(mock.log_messages, { level = "debug", msg = msg })
    end,
    info = function(msg)
      mock.log_messages = mock.log_messages or {}
      table.insert(mock.log_messages, { level = "info", msg = msg })
    end,
    warn = function(msg)
      mock.log_messages = mock.log_messages or {}
      table.insert(mock.log_messages, { level = "warn", msg = msg })
    end,
    error = function(msg)
      mock.log_messages = mock.log_messages or {}
      table.insert(mock.log_messages, { level = "error", msg = msg })
    end
  }

  -- Inyectar los mocks en el entorno global
  _G.vim = mock.vim
  package.loaded["copilotchatassist.utils.log"] = log

  -- Mock para detector
  local detector = {
    _get_language_handler = function(filetype)
      if filetype == "java" then
        return package.loaded["copilotchatassist.documentation.language.java"]
      else
        return package.loaded["copilotchatassist.documentation.language.elixir"]
      end
    end,
    ISSUE_TYPES = {
      MISSING = "missing",
      OUTDATED = "outdated",
      INCOMPLETE = "incomplete"
    }
  }
  package.loaded["copilotchatassist.documentation.detector"] = detector

  -- Mock para common (utilizado por los módulos de lenguaje)
  local common = {
    find_doc_block = function() return nil end,
    is_documentation_outdated = function() return false end,
    is_documentation_incomplete = function() return false end,
    normalize_documentation = function(doc) return doc end
  }
  package.loaded["copilotchatassist.documentation.language.common"] = common

  return true
end

-- Función para limpiar el estado entre pruebas
local function reset_test_state()
  mock.buffer_content = {}
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Limpiar los módulos cargados para asegurar estado fresco
  for k, v in pairs(package.loaded) do
    if k:match("^copilotchatassist%.documentation%.language%.") then
      package.loaded[k] = nil
    end
  end
end

------------------------------------------
-- CASOS DE PRUEBA PARA JAVA
------------------------------------------

-- Test 1: Verificación básica del posicionamiento JavaDoc antes de anotaciones
tests.java_service_annotation_basic = function()
  reset_test_state()
  vim.bo[1].filetype = "java"

  -- Configurar el buffer con el ejemplo Java
  mock.buffer_content = {
    "package com.example.demo;",
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

  -- Cargar el módulo Java
  local java_handler = require("copilotchatassist.documentation.language.java")

  -- JavaDoc a aplicar
  local doc_block = [[/**
 * Example service for demonstration purposes.
 */]]

  -- Aplicar documentación a la clase (línea 5)
  local result = java_handler.apply_documentation(1, 5, doc_block)

  -- Verificar que el resultado es exitoso
  if not result then
    return false, "La aplicación de la documentación falló"
  end

  -- Verificar que la documentación se insertó antes de la anotación @Service
  if not mock.modified_content or mock.modified_content.start >= 5 then
    return false, "La documentación no se insertó antes de la anotación @Service (línea " ..
                  (mock.modified_content and mock.modified_content.start + 1 or "N/A") .. ")"
  end

  return true
end

-- Test 2: Verificación con múltiples anotaciones
tests.java_multiple_annotations = function()
  reset_test_state()
  vim.bo[1].filetype = "java"

  -- Configurar el buffer con ejemplo de múltiples anotaciones
  mock.buffer_content = {
    "package com.example.demo;",
    "",
    "import org.springframework.stereotype.Service;",
    "import org.springframework.transaction.annotation.Transactional;",
    "",
    "@Service",
    "@Transactional",
    "public class MultiAnnotationService {",
    "",
    "  public void doSomething() {",
    "    // Implementation",
    "  }",
    "}"
  }

  -- Cargar el módulo Java
  local java_handler = require("copilotchatassist.documentation.language.java")

  -- JavaDoc a aplicar
  local doc_block = [[/**
 * Service with multiple annotations.
 */]]

  -- Aplicar documentación a la clase (línea 6)
  local result = java_handler.apply_documentation(1, 6, doc_block)

  -- Verificar que el resultado es exitoso
  if not result then
    return false, "La aplicación de la documentación falló"
  end

  -- Verificar que la documentación se insertó antes de la primera anotación @Service
  if not mock.modified_content or mock.modified_content.start >= 6 then
    return false, "La documentación no se insertó antes de la primera anotación (línea " ..
                  (mock.modified_content and mock.modified_content.start + 1 or "N/A") .. ")"
  end

  return true
end

-- Test 3: Caso de anotaciones con línea en blanco antes
tests.java_annotation_with_blank_line = function()
  reset_test_state()
  vim.bo[1].filetype = "java"

  -- Configurar el buffer con ejemplo de anotación con línea en blanco antes
  mock.buffer_content = {
    "package com.example.demo;",
    "",
    "import org.springframework.stereotype.Service;",
    "",
    "",
    "@Service",
    "public class ServiceWithBlankLine {",
    "",
    "  public void doSomething() {",
    "    // Implementation",
    "  }",
    "}"
  }

  -- Cargar el módulo Java
  local java_handler = require("copilotchatassist.documentation.language.java")

  -- JavaDoc a aplicar
  local doc_block = [[/**
 * Service with blank line before annotation.
 */]]

  -- Aplicar documentación a la clase (línea 6)
  local result = java_handler.apply_documentation(1, 6, doc_block)

  -- Verificar que el resultado es exitoso
  if not result then
    return false, "La aplicación de la documentación falló"
  end

  -- Verificar que la documentación se insertó en la línea en blanco antes de la anotación
  if not mock.modified_content or mock.modified_content.start != 4 then
    return false, "La documentación no se insertó en la línea en blanco antes de la anotación (línea " ..
                  (mock.modified_content and mock.modified_content.start + 1 or "N/A") .. " en lugar de línea 5)"
  end

  return true
end

-- Test 4: Caso específico que motivó la corrección original
tests.java_service_annotation_original_case = function()
  reset_test_state()
  vim.bo[1].filetype = "java"

  -- Configurar el buffer con el ejemplo exacto del problema reportado
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

  -- Cargar el módulo Java
  local java_handler = require("copilotchatassist.documentation.language.java")

  -- JavaDoc a aplicar
  local doc_block = [[/**
 * Mapper service for converting {@link ScheduleOverrideShiftEntity} entities to {@link OverrideShift} domain models.
 * <p>
 * This class provides methods to map persistence entities representing schedule override shifts into
 * domain objects used within the flexible schedules module.
 */]]

  -- Aplicar documentación a la clase (línea 10)
  local result = java_handler.apply_documentation(1, 10, doc_block)

  -- Verificar que el resultado es exitoso
  if not result then
    return false, "La aplicación de la documentación falló"
  end

  -- Verificar que la documentación se insertó antes de la anotación @Service
  if not mock.modified_content or mock.modified_content.start >= 9 then
    return false, "La documentación no se insertó antes de la anotación @Service (línea " ..
                  (mock.modified_content and mock.modified_content.start + 1 or "N/A") .. ")"
  end

  return true
end

------------------------------------------
-- CASOS DE PRUEBA PARA ELIXIR
------------------------------------------

-- Test 1: Verificación básica de detección de módulos Elixir con puntos
tests.elixir_module_detection_basic = function()
  reset_test_state()
  vim.bo[1].filetype = "elixir"

  -- Configurar el buffer con ejemplo Elixir básico
  mock.buffer_content = {
    "defmodule MyApp.MyModule do",
    "  def my_function do",
    "    :ok",
    "  end",
    "end"
  }

  -- Cargar el módulo Elixir
  local elixir_handler = require("copilotchatassist.documentation.language.elixir")

  -- Configurar para Elixir
  elixir_handler.setup_for_elixir(1)

  -- Escanear el buffer
  local items = elixir_handler.scan_buffer(1)

  -- Verificar que se detectó el módulo
  local module_found = false
  for _, item in ipairs(items) do
    if item.type == "module" and item.name == "MyApp.MyModule" then
      module_found = true
      break
    end
  end

  if not module_found then
    return false, "No se detectó correctamente el módulo MyApp.MyModule"
  end

  return true
end

-- Test 2: Verificación con módulo anidado profundamente
tests.elixir_nested_module_detection = function()
  reset_test_state()
  vim.bo[1].filetype = "elixir"

  -- Configurar el buffer con ejemplo de módulo anidado
  mock.buffer_content = {
    "defmodule Very.Deeply.Nested.Module.Structure do",
    "  def my_function do",
    "    :ok",
    "  end",
    "end"
  }

  -- Cargar el módulo Elixir
  local elixir_handler = require("copilotchatassist.documentation.language.elixir")

  -- Configurar para Elixir
  elixir_handler.setup_for_elixir(1)

  -- Escanear el buffer
  local items = elixir_handler.scan_buffer(1)

  -- Verificar que se detectó el módulo
  local module_found = false
  for _, item in ipairs(items) do
    if item.type == "module" and item.name == "Very.Deeply.Nested.Module.Structure" then
      module_found = true
      break
    end
  end

  if not module_found then
    return false, "No se detectó correctamente el módulo anidado Very.Deeply.Nested.Module.Structure"
  end

  return true
end

-- Test 3: Caso específico que motivó la corrección original
tests.elixir_controller_original_case = function()
  reset_test_state()
  vim.bo[1].filetype = "elixir"

  -- Configurar el buffer con el ejemplo exacto del problema reportado
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

  -- Cargar el módulo Elixir
  local elixir_handler = require("copilotchatassist.documentation.language.elixir")

  -- Configurar para Elixir
  elixir_handler.setup_for_elixir(1)

  -- Escanear el buffer
  local items = elixir_handler.scan_buffer(1)

  -- Verificar que se detectó el módulo
  local module_found = false
  for _, item in ipairs(items) do
    if item.type == "module" and item.name == "IrSchedulesFacadeWeb.CustomShiftsController" then
      module_found = true
      break
    end
  end

  if not module_found then
    return false, "No se detectó correctamente el módulo IrSchedulesFacadeWeb.CustomShiftsController"
  end

  -- Probar aplicación de documentación al módulo
  local module_doc = "@moduledoc \"\"\"\nControlador para gestionar turnos personalizados.\n\"\"\""
  local result = elixir_handler.apply_documentation(1, 1, module_doc)

  if not result or not mock.modified_content then
    return false, "No se pudo aplicar documentación al módulo"
  end

  return true
end

-- Test 4: Caso avanzado con formato de módulo inusual (con espacios adicionales)
tests.elixir_unusual_module_format = function()
  reset_test_state()
  vim.bo[1].filetype = "elixir"

  -- Configurar el buffer con formato inusual pero válido
  mock.buffer_content = {
    "defmodule   IrSchedulesFacadeWeb.Unusual.Spacing.Module   do",
    "  def test do",
    "    :ok",
    "  end",
    "end"
  }

  -- Cargar el módulo Elixir
  local elixir_handler = require("copilotchatassist.documentation.language.elixir")

  -- Configurar para Elixir
  elixir_handler.setup_for_elixir(1)

  -- Escanear el buffer
  local items = elixir_handler.scan_buffer(1)

  -- Verificar que se detectó el módulo a pesar del formato inusual
  local module_found = false
  local detected_name = ""
  for _, item in ipairs(items) do
    if item.type == "module" then
      detected_name = item.name
      if item.name == "IrSchedulesFacadeWeb.Unusual.Spacing.Module" then
        module_found = true
      end
      break
    end
  end

  if not module_found then
    return false, "No se detectó correctamente el módulo con espacios inusuales. Nombre detectado: " ..
                  (detected_name ~= "" and detected_name or "ninguno")
  end

  return true
end

------------------------------------------
-- EJECUTOR DE PRUEBAS
------------------------------------------

local function run_all_tests()
  print_header("SCRIPT DE VALIDACIÓN CONTINUA DE FUNCIONALIDADES")

  -- Configurar el entorno de pruebas
  local setup_ok = setup_test_env()
  if not setup_ok then
    print("❌ ERROR: No se pudo configurar el entorno de pruebas")
    return false
  end

  -- Ejecutar pruebas Java
  print_subheader("PRUEBAS JAVA - POSICIONAMIENTO DE DOCUMENTACIÓN ANTES DE ANOTACIONES")

  for name, test_func in pairs(tests) do
    if name:match("^java_") then
      local success, error_message = test_func()
      print_result(name, success, error_message)
    end
  end

  -- Ejecutar pruebas Elixir
  print_subheader("PRUEBAS ELIXIR - DETECCIÓN DE MÓDULOS CON NOMBRES COMPUESTOS")

  for name, test_func in pairs(tests) do
    if name:match("^elixir_") then
      local success, error_message = test_func()
      print_result(name, success, error_message)
    end
  end

  -- Mostrar resultados finales
  print_header("RESULTADOS FINALES")

  local total_tests = 0
  for _ in pairs(tests) do
    total_tests = total_tests + 1
  end

  print("Total de pruebas ejecutadas: " .. total_tests)
  print("Pruebas exitosas: " .. successes)
  print("Pruebas fallidas: " .. #failures)

  if #failures > 0 then
    print("\nDetalle de las pruebas fallidas:")
    for i, failure in ipairs(failures) do
      print(i .. ". " .. failure.name .. ": " .. failure.message)
    end
    print("\n❌ VALIDACIÓN FALLIDA: Algunas pruebas no pasaron.")
    return false
  else
    print("\n✅ VALIDACIÓN EXITOSA: Todas las pruebas pasaron correctamente.")
    return true
  end
end

-- Ejecutar todas las pruebas
local success = run_all_tests()

-- Devolver código de salida según el resultado
if not success then
  os.exit(1)
else
  os.exit(0)
end