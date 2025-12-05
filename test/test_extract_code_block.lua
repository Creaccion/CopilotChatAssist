-- Test para validar el funcionamiento de la función extract_code_block
-- Este test es específico para la función de extracción de bloques de código

local script_path = debug.getinfo(1).source:match("@(.*/)")
script_path = script_path and script_path:sub(1, -6) or "" -- Quitar 'test/'
package.path = script_path .. "lua/?.lua;" .. package.path
package.path = script_path .. "?.lua;" .. package.path

-- Mock de log para pruebas
local log = {
  debug = function(msg) print("[DEBUG] " .. msg) end,
  info = function(msg) print("[INFO] " .. msg) end,
  warn = function(msg) print("[WARN] " .. msg) end,
  error = function(msg) print("[ERROR] " .. msg) end
}

-- Inyectar mock de log
package.loaded["copilotchatassist.utils.log"] = log

-- Importar el módulo a probar
local utils = require("copilotchatassist.utils")

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

-- PRUEBA 1: Extracción de código del formato normal de bloque de código
function test_extract_code_block_normal()
  print_header("PRUEBA: Extracción de código de formato normal")

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

  -- Comparar caracter por caracter para diagnosticar diferencias
  local success = code_block == expected

  if not success then
    print("Esperado:\n" .. expected)
    print("\nObtenido:\n" .. code_block)

    print("\nDiagnóstico de diferencias:")
    print("Longitud esperada: " .. #expected)
    print("Longitud obtenida: " .. #code_block)

    -- Mostrar posición exacta de la diferencia
    for i = 1, math.min(#expected, #code_block) do
      if expected:sub(i,i) ~= code_block:sub(i,i) then
        print("Primera diferencia en posición " .. i)
        print("Caracter esperado: '" .. expected:sub(i,i) .. "' (código: " .. string.byte(expected:sub(i,i)) .. ")")
        print("Caracter obtenido: '" .. code_block:sub(i,i) .. "' (código: " .. string.byte(code_block:sub(i,i)) .. ")")
        break
      end
    end

    -- Imprimir representación de bytes para diagnóstico
    print("\nBytes del resultado (primeros 20):")
    local bytes = {}
    for i = 1, math.min(20, #code_block) do
      table.insert(bytes, string.byte(code_block:sub(i,i)))
    end
    print(table.concat(bytes, ", "))
  end

  print_result("Extracción de código formato patch", success)
  return success
end

-- PRUEBA 3: Selección del bloque de código más grande entre múltiples
function test_select_largest_code_block()
  print_header("PRUEBA: Selección del bloque de código más grande")

  local response = [[
Aquí tienes un ejemplo pequeño:

```java
class Small {
}
```

Y aquí está el bloque de código más grande que deberías seleccionar:

```java
package test;

/**
 * Una clase de ejemplo más grande
 */
public class LargerExample {
    /**
     * Un método de ejemplo
     */
    public void test() {
    }

    /**
     * Otro método de ejemplo
     */
    public void anotherTest() {
    }
}
```

Y finalmente otro bloque pequeño:

```java
class AnotherSmall {
}
```
]]

  local code_block = utils.extract_code_block(response)

  local expected = [[package test;

/**
 * Una clase de ejemplo más grande
 */
public class LargerExample {
    /**
     * Un método de ejemplo
     */
    public void test() {
    }

    /**
     * Otro método de ejemplo
     */
    public void anotherTest() {
    }
}]]

  local success = code_block == expected

  if not success then
    print("Esperado:\n" .. expected)
    print("\nObtenido:\n" .. code_block)
  end

  print_result("Selección del bloque de código más grande", success)
  return success
end

-- PRUEBA 4: Extracción de código sin marcadores de formato
function test_extract_code_without_markers()
  print_header("PRUEBA: Extracción de código sin marcadores")

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

  local code_block = utils.extract_code_block(response)

  local expected = response

  local success = code_block == expected

  if not success then
    print("Esperado:\n" .. expected)
    print("\nObtenido:\n" .. code_block)
  end

  print_result("Extracción de código sin marcadores", success)
  return success
end

-- PRUEBA 5: Soporte para diferentes lenguajes en formato de patch
function test_patch_format_different_languages()
  print_header("PRUEBA: Soporte para diferentes lenguajes en formato patch")

  local response = [[
```python path=/path/to/example.py start_line=1 end_line=15 mode=replace
#!/usr/bin/env python3
"""
Módulo de ejemplo
"""

class Example:
    """
    Una clase de ejemplo en Python
    """

    def test(self):
        """
        Un método de ejemplo
        """
        pass
``` end
]]

  local code_block = utils.extract_code_block(response)

  local expected = [[#!/usr/bin/env python3
"""
Módulo de ejemplo
"""

class Example:
    """
    Una clase de ejemplo en Python
    """

    def test(self):
        """
        Un método de ejemplo
        """
        pass]]

  -- Comparar caracter por caracter para diagnosticar diferencias
  local success = code_block == expected

  if not success then
    print("Esperado:\n" .. expected)
    print("\nObtenido:\n" .. code_block)

    print("\nDiagnóstico de diferencias:")
    print("Longitud esperada: " .. #expected)
    print("Longitud obtenida: " .. #code_block)

    -- Mostrar posición exacta de la diferencia
    for i = 1, math.min(#expected, #code_block) do
      if expected:sub(i,i) ~= code_block:sub(i,i) then
        print("Primera diferencia en posición " .. i)
        print("Caracter esperado: '" .. expected:sub(i,i) .. "' (código: " .. string.byte(expected:sub(i,i)) .. ")")
        print("Caracter obtenido: '" .. code_block:sub(i,i) .. "' (código: " .. string.byte(code_block:sub(i,i)) .. ")")
        break
      end
    end

    -- Imprimir representación de bytes para diagnóstico
    print("\nBytes del resultado (primeros 20):")
    local bytes = {}
    for i = 1, math.min(20, #code_block) do
      table.insert(bytes, string.byte(code_block:sub(i,i)))
    end
    print(table.concat(bytes, ", "))
  end

  print_result("Soporte para diferentes lenguajes en formato patch", success)
  return success
end

-- Ejecutar todas las pruebas
print_header("EJECUTANDO TODAS LAS PRUEBAS")

local test_results = {
  test_extract_code_block_normal(),
  test_extract_code_block_patch(),
  test_select_largest_code_block(),
  test_extract_code_without_markers(),
  test_patch_format_different_languages()
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