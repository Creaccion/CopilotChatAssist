-- Test para la documentación de Java
-- Este archivo contiene pruebas para verificar el correcto funcionamiento
-- de la documentación en archivos Java, con especial énfasis en records y anotaciones

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
    return require("copilotchatassist.documentation.language.java")
  end,
  ISSUE_TYPES = {
    MISSING = "missing",
    OUTDATED = "outdated",
    INCOMPLETE = "incomplete"
  }
}

-- Casos de prueba
local tests = {}

-- Test 1: Prueba de documentación en una clase Java con anotaciones
tests.test_java_class_with_annotations = function()
  -- Configurar el buffer con una clase Java con anotaciones
  mock.buffer_content = {
    "package com.example;",
    "",
    "import java.util.List;",
    "import java.util.Map;",
    "",
    "@Service",
    "public class ExampleService {",
    "    ",
    "    private final Repository repository;",
    "    ",
    "    public ExampleService(Repository repository) {",
    "        this.repository = repository;",
    "    }",
    "    ",
    "    public List<Item> getItems() {",
    "        return repository.findAll();",
    "    }",
    "}"
  }

  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Cargar el módulo de Java
  local java_handler = require("copilotchatassist.documentation.language.java")

  -- Aplicar documentación a la clase
  local doc_block = "/**\n * Servicio que proporciona acceso a los items.\n *\n * @since 1.0\n */"
  local result = java_handler.apply_documentation(1, 6, doc_block)

  -- Verificar que la documentación se insertó antes de la anotación
  assert(result, "La documentación debería haberse aplicado correctamente")
  assert(mock.modified_content, "El buffer debería haber sido modificado")
  assert(mock.modified_content.start == 5, "La documentación debería haberse insertado antes de la línea 6")

  -- Verificar el contenido de la documentación
  local doc_lines = mock.modified_content.lines
  assert(#doc_lines > 0, "La documentación debería tener al menos una línea")
  assert(doc_lines[1]:match("/%*%*"), "La primera línea debería comenzar con /**")
  assert(doc_lines[#doc_lines]:match("%*/"), "La última línea debería terminar con */")

  print("✅ Test test_java_class_with_annotations pasado")
end

-- Test 2: Prueba de documentación en un record de Java
tests.test_java_record = function()
  -- Configurar el buffer con un record Java
  mock.buffer_content = {
    "package com.example;",
    "",
    "import java.util.List;",
    "",
    "public record Person(String name, int age, String email) {",
    "    public Person {",
    "        if (age < 0) {",
    "            throw new IllegalArgumentException(\"Age cannot be negative\");",
    "        }",
    "    }",
    "    ",
    "    public boolean isAdult() {",
    "        return age >= 18;",
    "    }",
    "}"
  }

  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Cargar el módulo de Java
  local java_handler = require("copilotchatassist.documentation.language.java")

  -- Aplicar documentación al record
  local doc_block = "/**\n * Representa una persona con nombre, edad y email.\n *\n * @param name Nombre de la persona\n * @param age Edad de la persona\n * @param email Email de la persona\n */"
  local result = java_handler.apply_documentation(1, 5, doc_block)

  -- Verificar que la documentación se insertó correctamente
  assert(result, "La documentación debería haberse aplicado correctamente")
  assert(mock.modified_content, "El buffer debería haber sido modificado")

  -- Verificar el contenido de la documentación
  local doc_lines = mock.modified_content.lines
  assert(#doc_lines > 0, "La documentación debería tener al menos una línea")
  assert(doc_lines[1]:match("/%*%*"), "La primera línea debería comenzar con /**")
  assert(doc_lines[#doc_lines]:match("%*/"), "La última línea debería terminar con */")

  print("✅ Test test_java_record pasado")
end

-- Test 3: Prueba de documentación con anotaciones en un método
tests.test_java_method_with_annotations = function()
  -- Configurar el buffer con un método con anotaciones
  mock.buffer_content = {
    "package com.example;",
    "",
    "import java.util.List;",
    "",
    "public class ApiController {",
    "    ",
    "    @GetMapping(\"/api/items\")",
    "    @ResponseBody",
    "    public List<Item> getItems() {",
    "        return service.findAll();",
    "    }",
    "}"
  }

  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Cargar el módulo de Java
  local java_handler = require("copilotchatassist.documentation.language.java")

  -- Aplicar documentación al método
  local doc_block = "/**\n * Obtiene la lista de todos los items disponibles.\n *\n * @return Lista de items\n */"
  local result = java_handler.apply_documentation(1, 7, doc_block)

  -- Verificar que la documentación se insertó antes de las anotaciones
  assert(result, "La documentación debería haberse aplicado correctamente")
  assert(mock.modified_content, "El buffer debería haber sido modificado")
  assert(mock.modified_content.start == 6, "La documentación debería haberse insertado antes de la línea 7")

  print("✅ Test test_java_method_with_annotations pasado")
end

-- Ejecutar todas las pruebas
local function run_all_tests()
  print("\n=== EJECUTANDO PRUEBAS DE DOCUMENTACIÓN JAVA ===\n")

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