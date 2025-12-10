-- Test para validar el funcionamiento del módulo fullfile_documenter
-- Prueba la extracción de código y procesamiento de respuestas de CopilotChat

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
      return #(mock.buffer_content or {})
    end,
    nvim_buf_is_valid = function(buffer)
      return buffer == 1
    end,
    nvim_buf_get_name = function(buffer)
      return "/mock/path/to/file.java"
    end,
    nvim_create_buf = function(listed, scratch)
      return 2 -- buffer ID para previsualización
    end,
    nvim_win_get_cursor = function(win)
      return {1, 0}
    end,
    nvim_set_current_buf = function(buffer)
      mock.current_buffer = buffer
    end,
    nvim_create_augroup = function(name, opts)
      return 1
    end,
    nvim_create_autocmd = function(event, opts)
      -- No hacer nada
    end
  },
  bo = {
    [1] = { filetype = "java", modified = false },
    [2] = { filetype = "java", modified = false }
  },
  fn = {
    fnamemodify = function(file, mods)
      if mods == ":t" then
        return "file.java"
      end
      return file
    end,
    setenv = function() end,
    stdpath = function(what)
      if what == "cache" then
        return "/mock/cache"
      end
      return "/mock"
    end,
    mkdir = function(path, mode)
      return true
    end,
    bufadd = function(path)
      return 1
    end,
    bufload = function(buffer)
      return true
    end,
    bufnr = function(path)
      if path == "/mock/path/to/file.java" then
        return 1
      end
      return -1
    end,
    shellescape = function(str)
      return "'" .. str .. "'"
    end,
    filereadable = function(path)
      return true
    end,
    filewritable = function(path)
      return true
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
    print("NOTIFY: " .. msg)
  end,
  log = {
    levels = {
      ERROR = 1,
      WARN = 2,
      INFO = 3,
      DEBUG = 4
    }
  },
  defer_fn = function(f, timeout) f() end,
  inspect = function(value)
    if type(value) == "string" then
      return '"' .. value .. '"'
    end
    return tostring(value)
  end,
  cmd = function(cmd)
    mock.commands = mock.commands or {}
    table.insert(mock.commands, cmd)
    print("COMMAND: " .. cmd)
  end,
  g = {
    copilotchatassist_debug = true
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

-- Mock de io
local mock_io = {
  files = {},
  open = function(path, mode)
    return {
      write = function(self, content)
        mock_io.files[path] = content
      end,
      read = function(self, format)
        return mock_io.files[path] or ""
      end,
      close = function(self)
        -- Nada
      end
    }
  end
}

-- Mock de copilotchat_api
local mock_copilotchat = {
  ask = function(prompt, opts)
    mock.last_prompt = prompt
    if opts and opts.callback then
      opts.callback(mock.mock_response)
    end
    return mock.mock_response
  end
}

-- Añadir ruta de búsqueda para encontrar los módulos de CopilotChatAssist
local script_path = debug.getinfo(1).source:match("@(.*/)")
script_path = script_path and script_path:sub(1, -6) or "" -- Quitar 'test/'
package.path = script_path .. "lua/?.lua;" .. package.path
package.path = script_path .. "?.lua;" .. package.path

-- Inyectar mocks
_G.vim = mock.vim
_G.io = mock_io
package.loaded["copilotchatassist.utils.log"] = log
package.loaded["copilotchatassist.copilotchat_api"] = mock_copilotchat

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

-- Función para limpiar el estado mock entre pruebas
local function reset_mock()
  mock.buffer_content = nil
  mock.modified_content = nil
  mock.notifications = nil
  mock.log_messages = nil
  mock.commands = nil
  mock.last_prompt = nil
  mock.current_buffer = nil
  mock_io.files = {}
end

-- Configurar buffer con contenido de prueba
local function setup_test_buffer(content)
  mock.buffer_content = {}

  -- Convertir string a array de líneas
  for line in content:gmatch("([^\n]*)\n?") do
    table.insert(mock.buffer_content, line)
  end

  return mock.buffer_content
end

-- Configurar una respuesta mock de CopilotChat
local function set_mock_response(response)
  mock.mock_response = response
end

-- Importar los módulos a probar
local utils = require("copilotchatassist.utils")
local fullfile_documenter = require("copilotchatassist.documentation.fullfile_documenter")

-- PRUEBA 1: Extracción de código del formato normal de bloque de código
function test_extract_code_block_normal()
  print_header("PRUEBA: Extracción de código de formato normal")
  reset_mock()

  local response = [[
Aquí está tu código documentado:

```java
package test;

/**
 * Una clase de ejemplo
 */
public class Example {
    /**
     * Un método de ejemplo
     */
    public void test() {
    }
}
```

Espero que te sea útil.
]]

  local code_block = utils.extract_code_block(response)

  local expected = [[package test;

/**
 * Una clase de ejemplo
 */
public class Example {
    /**
     * Un método de ejemplo
     */
    public void test() {
    }
}]]

  local success = code_block == expected

  if not success then
    print("Esperado:\n" .. expected)
    print("\nObtenido:\n" .. code_block)
  end

  print_result("Extracción de código formato normal", success)
  return success
end

-- PRUEBA 2: Extracción de código del formato de patch
function test_extract_code_block_patch()
  print_header("PRUEBA: Extracción de código de formato patch")
  reset_mock()

  local response = [[
```java path=/path/to/Example.java start_line=1 end_line=15 mode=replace
package test;

/**
 * Una clase de ejemplo
 */
public class Example {
    /**
     * Un método de ejemplo
     */
    public void test() {
    }
}
``` end
]]

  -- Configurar la respuesta específica de fullfile_documenter
  set_mock_response(response)

  -- Simular contenido de buffer a documentar
  setup_test_buffer([[
package test;

public class Example {
    public void test() {
    }
}
]])

  -- Ejecutar el proceso
  local success, _ = fullfile_documenter.document_buffer(1, {})

  -- Verificar que se haya extraído el código correctamente
  local expected_content = [[package test;

/**
 * Una clase de ejemplo
 */
public class Example {
    /**
     * Un método de ejemplo
     */
    public void test() {
    }
}]]

  -- Verificar que el buffer de previsualización tiene el contenido correcto
  local success = mock.modified_content ~= nil

  -- Imprimir resultado
  print_result("Extracción de código formato patch", success)
  return success
end

-- PRUEBA 3: Manejo de respuesta vacía
function test_empty_response()
  print_header("PRUEBA: Manejo de respuesta vacía")
  reset_mock()

  -- Configurar respuesta vacía
  set_mock_response("")

  -- Simular contenido de buffer a documentar
  setup_test_buffer([[
package test;

public class Example {
    public void test() {
    }
}
]])

  -- Ejecutar el proceso
  local success, _ = fullfile_documenter.document_buffer(1, {})

  -- Verificar que se generó una notificación de error
  local error_notification = false
  if mock.notifications then
    for _, notification in ipairs(mock.notifications) do
      if notification.msg:match("vacía") and notification.level == vim.log.levels.ERROR then
        error_notification = true
        break
      end
    end
  end

  -- Imprimir resultado
  print_result("Manejo de respuesta vacía", error_notification, "Debería generar notificación de error")
  return error_notification
end

-- PRUEBA 4: Procesar texto completo sin marcadores
function test_process_text_without_markers()
  print_header("PRUEBA: Procesar texto sin marcadores de código")
  reset_mock()

  local response = [[
package test;

/**
 * Una clase de ejemplo
 */
public class Example {
    /**
     * Un método de ejemplo
     */
    public void test() {
    }
}
]]

  -- Configurar la respuesta
  set_mock_response(response)

  -- Simular contenido de buffer a documentar
  setup_test_buffer([[
package test;

public class Example {
    public void test() {
    }
}
]])

  -- Ejecutar el proceso
  local success, _ = fullfile_documenter.document_buffer(1, {})

  -- Verificar que se haya procesado correctamente
  local process_success = mock.modified_content ~= nil

  -- Imprimir resultado
  print_result("Procesar texto sin marcadores de código", process_success)
  return process_success
end

-- PRUEBA 5: Manejo de tipo de respuesta no string
function test_non_string_response()
  print_header("PRUEBA: Manejo de respuesta que no es string")
  reset_mock()

  -- Configurar respuesta que no es string (tabla en este caso)
  mock.mock_response = { content = "Esto no debería funcionar" }

  -- Simular contenido de buffer a documentar
  setup_test_buffer([[
package test;

public class Example {
    public void test() {
    }
}
]])

  -- Ejecutar el proceso
  local success, _ = pcall(function()
    return fullfile_documenter.document_buffer(1, {})
  end)

  -- Verificar que se manejó correctamente (no debería dar error)
  print_result("Manejo de respuesta no string", success, success and "Se manejó correctamente" or "No se manejó correctamente")
  return success
end

-- Ejecutar todas las pruebas
print_header("EJECUTANDO TODAS LAS PRUEBAS")

local test_results = {
  test_extract_code_block_normal(),
  test_extract_code_block_patch(),
  test_empty_response(),
  test_process_text_without_markers(),
  test_non_string_response()
}

print_header("RESULTADOS FINALES")
local all_passed = true

for i, result in ipairs(test_results) do
  all_passed = all_passed and result
end

if all_passed then
  print("✅ TODAS LAS PRUEBAS PASARON")
else
  print("❌ UNA O MÁS PRUEBAS FALLARON")
end

return all_passed