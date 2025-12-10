-- Test para la documentación de Elixir
-- Este archivo contiene pruebas para verificar el correcto funcionamiento
-- de la documentación en archivos Elixir, con especial énfasis en módulos y funciones

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

-- Mock de log
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

-- Casos de prueba
local tests = {}

-- Test 1: Prueba de documentación en módulo Elixir
tests.test_elixir_module = function()
  -- Configurar el buffer con un módulo Elixir
  mock.buffer_content = {
    "defmodule ExampleModule do",
    "  alias Example.OtherModule",
    "  import Enum",
    "",
    "  def hello(name) do",
    "    \"Hello, #{name}!\"",
    "  end",
    "",
    "  def add(a, b) do",
    "    a + b",
    "  end",
    "end"
  }

  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Cargar el módulo de Elixir
  local elixir_handler = require("copilotchatassist.documentation.language.elixir")

  -- Configurar para Elixir
  elixir_handler.setup_for_elixir(1)

  -- Aplicar documentación al módulo
  local doc_block = "@moduledoc \"\"\"\nMódulo de ejemplo para demostrar la documentación.\n\n## Ejemplos\n\n    iex> ExampleModule.hello(\"world\")\n    \"Hello, world!\"\n\"\"\""
  local result = elixir_handler.apply_documentation(1, 1, doc_block)

  -- Verificar que la documentación se insertó correctamente
  assert(result, "La documentación debería haberse aplicado correctamente")
  assert(mock.modified_content, "El buffer debería haber sido modificado")
  assert(mock.modified_content.start == 0, "La documentación debería haberse insertado al principio del módulo")

  -- Verificar el contenido de la documentación
  local doc_lines = mock.modified_content.lines
  assert(#doc_lines > 0, "La documentación debería tener al menos una línea")
  assert(doc_lines[1]:match("@moduledoc"), "La primera línea debería contener @moduledoc")

  print("✅ Test test_elixir_module pasado")
end

-- Test 2: Prueba de documentación en una función Elixir
tests.test_elixir_function = function()
  -- Configurar el buffer con un módulo y funciones Elixir
  mock.buffer_content = {
    "defmodule ExampleModule do",
    "  @moduledoc \"\"\"",
    "  Módulo de ejemplo para demostrar la documentación.",
    "  \"\"\"",
    "",
    "  def hello(name) do",
    "    \"Hello, #{name}!\"",
    "  end",
    "",
    "  def add(a, b) do",
    "    a + b",
    "  end",
    "end"
  }

  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Cargar el módulo de Elixir
  local elixir_handler = require("copilotchatassist.documentation.language.elixir")

  -- Aplicar documentación a una función
  local doc_block = "@doc \"\"\"\nSaluda a un usuario por su nombre.\n\n## Parámetros\n\n- name: Nombre del usuario a saludar\n\n## Ejemplos\n\n    iex> ExampleModule.hello(\"world\")\n    \"Hello, world!\"\n\"\"\""
  local result = elixir_handler.apply_documentation(1, 6, doc_block)

  -- Verificar que la documentación se insertó correctamente
  assert(result, "La documentación debería haberse aplicado correctamente")
  assert(mock.modified_content, "El buffer debería haber sido modificado")
  assert(mock.modified_content.start == 5, "La documentación debería haberse insertado antes de la función")

  -- Verificar el contenido de la documentación
  local doc_lines = mock.modified_content.lines
  assert(#doc_lines > 0, "La documentación debería tener al menos una línea")
  assert(doc_lines[1]:match("@doc"), "La primera línea debería contener @doc")

  print("✅ Test test_elixir_function pasado")
end

-- Test 3: Prueba de documentación en una función Elixir con pattern matching y cláusula when
tests.test_elixir_function_with_pattern_matching = function()
  -- Configurar el buffer con un módulo y funciones con pattern matching
  mock.buffer_content = {
    "defmodule ExampleModule do",
    "  @moduledoc \"\"\"",
    "  Módulo de ejemplo para demostrar la documentación.",
    "  \"\"\"",
    "",
    "  def process_user(%{name: name, age: age}) when is_binary(name) and age >= 18 do",
    "    {:ok, \"User #{name} is an adult\"}",
    "  end",
    "",
    "  def process_user(%{name: name, age: age}) when is_binary(name) do",
    "    {:error, \"User #{name} is not an adult\"}",
    "  end",
    "",
    "  def process_user(_) do",
    "    {:error, \"Invalid user data\"}",
    "  end",
    "end"
  }

  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Cargar el módulo de Elixir
  local elixir_handler = require("copilotchatassist.documentation.language.elixir")

  -- Aplicar documentación a la función con pattern matching
  local doc_block = "@doc \"\"\"\nProcesa información de un usuario adulto.\n\n## Parámetros\n\n- usuario: Mapa con `:name` y `:age`\n\n## Retorno\n\nRetorna una tupla `{:ok, message}` si el usuario es adulto.\n\"\"\""
  local result = elixir_handler.apply_documentation(1, 6, doc_block)

  -- Verificar que la documentación se insertó correctamente
  assert(result, "La documentación debería haberse aplicado correctamente")
  assert(mock.modified_content, "El buffer debería haber sido modificado")
  assert(mock.modified_content.start == 5, "La documentación debería haberse insertado antes de la función")

  -- Verificar el contenido de la documentación
  local doc_lines = mock.modified_content.lines
  assert(#doc_lines > 0, "La documentación debería tener al menos una línea")
  assert(doc_lines[1]:match("@doc"), "La primera línea debería contener @doc")

  print("✅ Test test_elixir_function_with_pattern_matching pasado")
end

-- Test 4: Prueba de actualización de documentación existente en módulo
tests.test_elixir_update_module_doc = function()
  -- Configurar el buffer con un módulo que ya tiene documentación
  mock.buffer_content = {
    "defmodule ExampleModule do",
    "  @moduledoc \"\"\"",
    "  Documentación antigua que será actualizada.",
    "  \"\"\"",
    "",
    "  def hello(name) do",
    "    \"Hello, #{name}!\"",
    "  end",
    "end"
  }

  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Cargar el módulo de Elixir
  local elixir_handler = require("copilotchatassist.documentation.language.elixir")

  -- Actualizar documentación existente
  local updated_doc = "@moduledoc \"\"\"\nMódulo de ejemplo con documentación actualizada.\n\n## Funciones\n\n- `hello/1`: Saluda a un usuario\n\"\"\""
  local result = elixir_handler.update_documentation(1, 2, 4, updated_doc)

  -- Verificar que la documentación se actualizó correctamente
  assert(result, "La documentación debería haberse actualizado correctamente")
  assert(mock.modified_content, "El buffer debería haber sido modificado")
  assert(mock.modified_content.start == 1, "La documentación debería haberse actualizado desde la línea 2")
  assert(mock.modified_content.end_line == 4, "La documentación debería haberse actualizado hasta la línea 4")

  -- Verificar el contenido de la documentación actualizada
  local doc_lines = mock.modified_content.lines
  assert(#doc_lines > 0, "La documentación debería tener al menos una línea")
  assert(doc_lines[1]:match("@moduledoc"), "La primera línea debería contener @moduledoc")
  assert(table.concat(doc_lines, "\n"):match("actualizada"), "La documentación debería contener el texto actualizado")

  print("✅ Test test_elixir_update_module_doc pasado")
end

-- Ejecutar todas las pruebas
local function run_all_tests()
  print("\n=== EJECUTANDO PRUEBAS DE DOCUMENTACIÓN ELIXIR ===\n")

  local all_passed = true
  local count = 0

  for name, test_func in pairs(tests) do
    count = count + 1
    local success, err = pcall(test_func)
    if not success then
      print("❌ " .. name .. " falló: " .. tostring(err))
      all_passed = false
    end
  end

  print("\n=== RESULTADOS ===")
  if all_passed then
    print("✅ Todos los " .. count .. " tests pasaron exitosamente")
  else
    print("❌ Hubo errores en las pruebas")
  end
end

-- Ejecutar las pruebas
run_all_tests()