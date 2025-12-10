# Correcciones de Formato para la Documentación

Este documento propone soluciones para los problemas identificados en el formato de documentación generada para Java y Elixir.

## Problemas Detectados

### Java
1. **Documentación duplicada**: El sistema está insertando bloques JavaDoc en múltiples lugares, incluyendo:
   - Un bloque de documentación general antes de la anotación `@Service`
   - Un bloque de documentación específico para el método `toDomain` que queda "flotante" entre los imports y la clase

2. **Posicionamiento incorrecto**: Aunque la corrección para colocar la documentación antes de las anotaciones funciona, el sistema no detecta ni maneja apropiadamente la documentación existente.

### Elixir
1. **Secciones vacías**: La documentación generada incluye secciones como "Parameters", "Returns" y "Errors" que aparecen vacías.
2. **Documentación duplicada**: Se generan bloques de documentación tanto para el módulo (`@moduledoc`) como para las funciones (`@doc`) con contenido similar o incompleto.

## Soluciones Propuestas

### Para Java

#### 1. Detección y eliminación de documentación duplicada

Modificar la función `apply_documentation` en `lua/copilotchatassist/documentation/language/java.lua` para:

1. Escanear todo el archivo en busca de bloques JavaDoc existentes
2. Si se encuentra documentación cerca del objetivo (clase o método), reemplazarla en lugar de añadir nueva
3. Detectar documentación "flotante" (sin asociación clara con código) y eliminarla

```lua
-- Modificar la función apply_documentation
function M.apply_documentation(buffer, start_line, doc_block, item)
  -- Código existente...

  -- Paso adicional: Buscar documentación existente en todo el archivo
  local existing_docs = {}
  for i, line in ipairs(buffer_content) do
    if line:match("^%s*/%*%*") then
      local doc_start = i
      local doc_end = nil

      -- Buscar el final del bloque
      for j = i, math.min(i + 30, #buffer_content) do
        if buffer_content[j]:match("%*/") then
          doc_end = j
          break
        end
      end

      if doc_end then
        table.insert(existing_docs, {
          start = doc_start,
          ending = doc_end,
          -- Determinar si está asociado con código
          is_floating = not is_doc_associated_with_code(buffer_content, doc_end)
        })
      end
    end
  end

  -- Eliminar documentación flotante
  for i = #existing_docs, 1, -1 do
    local doc = existing_docs[i]
    if doc.is_floating then
      vim.api.nvim_buf_set_lines(buffer, doc.start - 1, doc.ending, false, {})
      -- Ajustar posiciones
      if start_line > doc.ending then
        start_line = start_line - (doc.ending - doc.start + 1)
      end
    end
  end

  -- Resto de la función...
end

-- Nueva función auxiliar para determinar si un bloque de documentación está asociado con código
function is_doc_associated_with_code(buffer_content, doc_end)
  -- Buscar código en las 3 líneas siguientes
  for i = doc_end + 1, math.min(doc_end + 3, #buffer_content) do
    local line = buffer_content[i]
    if line:match("^%s*public%s+") or
       line:match("^%s*class%s+") or
       line:match("^%s*interface%s+") or
       line:match("^%s*@[%w_]+") or
       line:match("^%s*[%w_.<>]+%s+[%w_]+%(") then
      return true
    end
  end
  return false
end
```

#### 2. Mejor asociación de documentación con elementos

Mejorar la función `scan_buffer` para asociar mejor la documentación con elementos:

```lua
function M.scan_buffer(buffer)
  -- Código existente...

  -- Después de encontrar un elemento:
  if item_name then
    -- Verificar si hay documentación existente
    local doc_info = M.find_doc_block(lines, i)

    -- Verificar también si hay documentación flotante asociada a este elemento
    if not doc_info then
      doc_info = find_floating_documentation_for_element(lines, i, item_name)
    end

    -- Resto del código...
  end
end

-- Nueva función para buscar documentación flotante que pueda estar asociada a un elemento
function find_floating_documentation_for_element(lines, element_line, element_name)
  -- Buscar en las 20 líneas anteriores
  for i = element_line - 1, math.max(1, element_line - 20), -1 do
    local line = lines[i]
    if line:match("^%s*/%*%*") then
      -- Verificar si esta documentación menciona el nombre del elemento
      local doc_start = i
      local doc_end = nil

      for j = i, math.min(i + 30, #lines) do
        if lines[j]:match("%*/") then
          doc_end = j
          break
        end

        -- Verificar si el nombre del elemento está mencionado
        if lines[j]:match(element_name) then
          -- Es probable que esta documentación pertenezca a este elemento
          -- Devolver información del bloque
          local doc_lines = {}
          for k = doc_start, doc_end do
            table.insert(doc_lines, lines[k])
          end

          return {
            start_line = doc_start,
            end_line = doc_end,
            lines = doc_lines,
            text = table.concat(doc_lines, "\n")
          }
        end
      end
    end
  end

  return nil
end
```

### Para Elixir

#### 1. Mejorar las plantillas de documentación

Modificar la función `normalize_documentation` en `lua/copilotchatassist/documentation/language/elixir.lua` para generar mejores plantillas:

```lua
function M.normalize_documentation(doc_block)
  -- Código existente...

  -- Si son comentarios regulares, convertir a formato @doc pero con mejor estructura
  if lines[1]:match("^%s*#") then
    -- En lugar de secciones vacías, crear una estructura básica más informativa
    table.insert(normalized_lines, "@doc \"\"\"")

    -- Extraer el contenido principal
    local main_content = {}
    local has_parameters = false
    local has_returns = false

    for _, line in ipairs(lines) do
      local content = line:gsub("^%s*#%s*", "")
      if content:match("^Parameters") or content:match("^Returns") or content:match("^Errors") then
        -- Ignorar secciones vacías
      else
        table.insert(main_content, content)
      end

      -- Detectar si hay información real de parámetros o retorno
      if line:match("@param") or line:match("param:") then
        has_parameters = true
      end
      if line:match("@return") or line:match("returns:") then
        has_returns = true
      end
    end

    -- Insertar contenido principal
    for _, line in ipairs(main_content) do
      table.insert(normalized_lines, line)
    end

    -- Solo añadir secciones si hay contenido para ellas
    if has_parameters then
      table.insert(normalized_lines, "## Parameters")
      -- Aquí podría extraerse la información de parámetros
    end

    if has_returns then
      table.insert(normalized_lines, "## Returns")
      -- Aquí podría extraerse la información de retorno
    end

    table.insert(normalized_lines, "\"\"\"")
  else
    -- Resto del código...
  end

  return table.concat(normalized_lines, "\n")
end
```

#### 2. Evitar la duplicación entre `@moduledoc` y `@doc`

Modificar la función `scan_buffer` para mejor discriminar entre documentación de módulo y de función:

```lua
function M.scan_buffer(buffer)
  -- Código existente...

  -- Al encontrar un módulo
  if module_name then
    -- Marcar claramente que es documentación de módulo
    table.insert(items, {
      name = module_name,
      type = "module",
      -- Otros campos...
    })
  end

  -- Al encontrar una función
  if func_name then
    -- Verificar si esta función es la función principal del módulo
    local is_main_function = func_name == "init" or func_name == "start" or func_name == "main"

    -- Si no es la función principal, documentarla por separado
    if not is_main_function then
      table.insert(items, {
        name = func_name,
        type = "function",
        -- Otros campos...
      })
    end
  end
end
```

#### 3. Mejorar la detección de contenido en secciones

```lua
function M.is_documentation_incomplete(buffer, doc_lines, param_names)
  -- Código existente...

  -- Verificar si hay secciones vacías
  local sections = {"Parameters", "Returns", "Errors"}
  local empty_sections = {}

  for _, section in ipairs(sections) do
    for i, line in ipairs(doc_lines) do
      -- Detectar encabezado de sección
      if line:match("^%s*#%s*" .. section .. "%s*$") or line:match("^%s*##%s*" .. section .. "%s*$") then
        -- Verificar si la siguiente línea tiene contenido significativo
        local next_line_index = i + 1
        if next_line_index > #doc_lines or
           doc_lines[next_line_index]:match("^%s*$") or
           doc_lines[next_line_index]:match("^%s*#") or
           doc_lines[next_line_index]:match("^%s*\"\"\"%s*$") then
          table.insert(empty_sections, section)
        end
      end
    end
  end

  -- Marcar como incompleto si hay secciones vacías
  if #empty_sections > 0 then
    return true
  end

  -- Resto del código...
end
```

## Plan de Implementación

1. **Java**:
   - Modificar la función `apply_documentation` para detectar y manejar documentación duplicada
   - Implementar la función `is_doc_associated_with_code` para distinguir documentación flotante
   - Actualizar `scan_buffer` para asociar mejor la documentación con elementos de código

2. **Elixir**:
   - Mejorar la función `normalize_documentation` para generar plantillas más útiles
   - Modificar `scan_buffer` para evitar duplicación entre documentación de módulo y función
   - Actualizar `is_documentation_incomplete` para detectar mejor secciones vacías

3. **Pruebas**:
   - Ejecutar el nuevo script `test_documentation_format.lua` para verificar las mejoras
   - Probar con archivos reales para validar el comportamiento en diferentes casos

## Mejoras Adicionales Recomendadas

1. **Mejor manejo contextual**: Determinar mediante análisis de contexto si un elemento ya tiene documentación existente, aunque no esté en la posición esperada.

2. **Preservación inteligente**: Al actualizar documentación, preservar secciones especiales o etiquetas específicas que puedan estar presentes.

3. **Detección heurística**: Utilizar heurísticas para determinar si una documentación flotante pertenece a una clase o método específico, basándose en la similitud de nombres y proximidad.

4. **Configuración de formato**: Permitir al usuario definir plantillas personalizadas para la documentación en diferentes lenguajes.

## Conclusión

Los problemas de formato en la documentación generada pueden resolverse mediante un mejor análisis del contexto del archivo, detección de documentación existente, y plantillas de documentación mejoradas. Las soluciones propuestas abordan tanto la duplicación de documentación como las secciones vacías, manteniendo al mismo tiempo la compatibilidad con las prácticas de documentación de cada lenguaje.