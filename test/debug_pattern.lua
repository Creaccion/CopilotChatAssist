-- Script para depurar el patrón de formato patch

local test = [[
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

print('Texto original a analizar:')
print(test)
print('------------------------')

-- Prueba con distintos patrones
local patterns = {
  -- Patrón 1: el original
  '```([%w_]+)%s+path=([^%s]+)[^`]*\\n(.-)\\n```%s*end',

  -- Patrón 2: captura voraz
  '```([%w_]+)%s+path=([^%s]+)[^`]*\\n(.*)\\n```%s*end',

  -- Patrón 3: usando posiciones
  '```([%w_]+)%s+path=([^%s]+)[^`]*\\n(.+)'
}

for i, pattern in ipairs(patterns) do
  print('------------------------')
  print('Patrón ' .. i .. ':')
  print(pattern)

  local lang, path, content = test:match(pattern)

  print('\nResultados:')
  print('lang: ' .. (lang or 'nil'))
  print('path: ' .. (path or 'nil'))
  print('content length: ' .. (content and #content or 'nil') .. ' caracteres')

  if content then
    print('Primeros 20 caracteres: "' .. content:sub(1, 20) .. '"')
    print('Últimos 20 caracteres: "' .. content:sub(-20) .. '"')
  end
end

-- Prueba 4: Procesamiento manual
print('------------------------')
print('Prueba 4: Procesamiento manual')

local start_marker = '```java path='
local end_marker = '``` end'

local start_pos = test:find(start_marker, 1, true)
local end_pos = test:find(end_marker, 1, true)

if start_pos and end_pos then
  local content_start = test:find('\n', start_pos) + 1
  local content_end = end_pos - 1

  local content = test:sub(content_start, content_end)

  print('\nResultados:')
  print('start_pos: ' .. start_pos)
  print('content_start: ' .. content_start)
  print('end_pos: ' .. end_pos)
  print('content_end: ' .. content_end)
  print('content length: ' .. #content .. ' caracteres')
  print('Contenido completo:')
  print(content)
end