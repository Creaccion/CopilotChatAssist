-- Módulo de utilidades para el asistente de documentación
-- Proporciona funciones auxiliares para la detección, generación y actualización de documentación

local M = {}
local log = require("copilotchatassist.utils.log")

-- Obtiene el contexto de una función (código relacionado)
-- @param bufnr número: ID del buffer
-- @param start_line número: Línea de inicio de la función
-- @param end_line número: Línea de fin de la función
-- @param context_lines número: Líneas adicionales de contexto (opcional)
-- @return string: Contexto de la función o cadena vacía si no se puede obtener
function M.get_function_context(bufnr, start_line, end_line, context_lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn("Buffer inválido al obtener contexto")
    return ""
  end

  -- Determinar cantidad de líneas de contexto
  context_lines = context_lines or 10
  local buffer_line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Calcular rango seguro de contexto
  local context_start = math.max(1, start_line - context_lines)
  local context_end = math.min(buffer_line_count, end_line + context_lines)

  -- Obtener líneas de contexto
  local lines = vim.api.nvim_buf_get_lines(bufnr, context_start - 1, context_end, false)
  if not lines or #lines == 0 then
    return ""
  end

  return table.concat(lines, "\n")
end

-- Busca ejemplos de estilo de documentación en el buffer
-- @param bufnr número: ID del buffer
-- @param max_examples número: Máximo número de ejemplos a encontrar
-- @return tabla: Lista de ejemplos de documentación encontrados
function M.get_documentation_style_examples(bufnr, max_examples)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn("Buffer inválido al buscar ejemplos de documentación")
    return {}
  end

  max_examples = max_examples or 3
  local filetype = vim.bo[bufnr].filetype
  local handler = require("copilotchatassist.documentation.detector")._get_language_handler(filetype)

  if not handler then
    log.warn("No hay manejador para el lenguaje al buscar ejemplos: " .. filetype)
    return {}
  end

  -- Usar el manejador específico del lenguaje para encontrar ejemplos
  local examples = handler.find_documentation_examples(bufnr, max_examples)
  return examples or {}
end

-- Extrae el bloque de documentación de una respuesta de CopilotChat
-- @param response string: Respuesta completa de CopilotChat
-- @return string: Bloque de documentación extraído o cadena vacía
function M.extract_documentation_from_response(response)
  if not response or response == "" then
    return ""
  end

  log.debug("Procesando respuesta de documentación de CopilotChat")

  -- Intentar extraer bloques de código con formato ```lenguaje\n...\n```
  local doc_block = response:match("```[%w_]*%s*\n(.-)\n```")

  if doc_block and doc_block ~= "" then
    log.debug("Bloque de código encontrado en la respuesta")
    return doc_block
  end

  -- Segundo intento: buscar bloques sin especificación de lenguaje
  doc_block = response:match("```\n(.-)\n```")

  if doc_block and doc_block ~= "" then
    log.debug("Bloque de código simple encontrado en la respuesta")
    return doc_block
  end

  -- Tercer intento: buscar bloques con lenguajes específicos
  local language_patterns = {
    "```lua\n(.-)\n```",
    "```python\n(.-)\n```",
    "```javascript\n(.-)\n```",
    "```typescript\n(.-)\n```",
    "```js\n(.-)\n```",
    "```ts\n(.-)\n```"
  }

  for _, pattern in ipairs(language_patterns) do
    doc_block = response:match(pattern)
    if doc_block and doc_block ~= "" then
      log.debug("Bloque de código con lenguaje específico encontrado en la respuesta")
      return doc_block
    end
  end

  -- Intentar extraer la documentación fuera de bloques de código
  -- Eliminar posibles instrucciones o explicaciones adicionales
  local cleaned_response = response

  -- Patrones comunes para eliminar
  local patterns_to_clean = {
    "^.*[Aa]quí está la documentación:?%s*",
    "^.*[Hh]ere'?s the documentation:?%s*",
    "^.*[Dd]ocumentation:?%s*",
    "^.*[Ll]a documentación actualizada:?%s*",
    "^.*[Uu]pdated documentation:?%s*",
    "^.*[Dd]ocumentación generada:?%s*",
    "^.*[Gg]enerated documentation:?%s*",
    "^.*[Aa]quí tienes la documentación:?%s*",
    "^.*[Hh]e mejorado la documentación:?%s*",
    "^.*[Ee]sta es la documentación:?%s*"
  }

  for _, pattern in ipairs(patterns_to_clean) do
    cleaned_response = cleaned_response:gsub(pattern, "")
  end

  -- Buscar bloques de comentarios por lenguaje
  local comments = {}
  local comment_patterns = {
    lua = function(line) return line:match("^%s*%-%-") end,
    python = function(line) return line:match("^%s*#") end,
    javascript = function(line) return line:match("^%s*//") or line:match("^%s*/%*") or line:match("^%s*%*") end,
    typescript = function(line) return line:match("^%s*//") or line:match("^%s*/%*") or line:match("^%s*%*") end,
    java = function(line) return line:match("^%s*//") or line:match("^%s*/%*%*") or line:match("^%s*%*") end
  }

  -- Detectar posibles comentarios de cualquier lenguaje soportado
  for line in cleaned_response:gmatch("[^\r\n]+") do
    for _, is_comment in pairs(comment_patterns) do
      if is_comment(line) then
        table.insert(comments, line)
        break
      end
    end
  end

  if #comments > 0 then
    log.debug("Comentarios de código encontrados directamente en la respuesta")
    return table.concat(comments, "\n")
  end

  -- Buscar bloques de texto que parecen documentación por sus patrones
  if cleaned_response:match("@param") or
     cleaned_response:match("@return") or
     cleaned_response:match("Parameters:") or
     cleaned_response:match("Returns:") or
     cleaned_response:match("Description:") then
    log.debug("Encontrados patrones de documentación en la respuesta")
    return cleaned_response
  end

  -- Verificar si hay líneas vacías (separadores de párrafos)
  -- y extraer solo la primera parte que probablemente sea la documentación
  local first_paragraph = cleaned_response:match("(.-)\n%s*\n")
  if first_paragraph and #first_paragraph > 30 then
    log.debug("Extrayendo primer párrafo como documentación")
    return first_paragraph
  end

  -- Buscar bloques JavaDoc completos
  local javadoc_start, javadoc_end = cleaned_response:match("(/%*%*[^*].-)(%*/)")
  if javadoc_start and javadoc_end then
    log.debug("Encontrado bloque JavaDoc completo")
    return javadoc_start .. javadoc_end
  end

  -- Buscar código entre bloques de triple backtick para Java (```java ... ```)
  local java_code = cleaned_response:match("```java(.-)```")
  if java_code then
    -- Ver si hay comentarios JavaDoc en ese código
    local javadoc_in_code = java_code:match("/%*%*.*%*/")
    if javadoc_in_code then
      log.debug("Encontrado JavaDoc dentro de un bloque de código Java")
      return javadoc_in_code
    end
  end

  -- Si no encontramos nada específico, devolver la respuesta limpia
  log.debug("Usando respuesta limpia como documentación")
  return cleaned_response
end

-- Normaliza el formato de documentación según las reglas de estilo
-- @param doc_block string: Bloque de documentación
-- @param filetype string: Tipo de archivo
-- @return string: Documentación normalizada
function M.normalize_documentation(doc_block, filetype)
  if not doc_block or doc_block == "" then
    return ""
  end

  -- Eliminar líneas vacías al inicio y al final
  doc_block = doc_block:gsub("^%s*(.-)%s*$", "%1")

  -- Normalizar según el tipo de archivo
  local handler = require("copilotchatassist.documentation.detector")._get_language_handler(filetype)
  if handler and handler.normalize_documentation then
    return handler.normalize_documentation(doc_block)
  end

  return doc_block
end

-- Determina el nivel de indentación de una línea de código
-- @param line string: Línea de código
-- @return número: Nivel de indentación (número de espacios)
function M.get_indent_level(line)
  if not line or line == "" then
    return 0
  end

  local indent = line:match("^(%s*)")
  return #indent
end

-- Aplica el nivel de indentación a un bloque de texto
-- @param text string: Texto a indentar
-- @param indent string: Indentación a aplicar (espacios o tabulaciones)
-- @return string: Texto indentado
function M.apply_indent(text, indent)
  if not text or text == "" then
    return ""
  end

  -- Si no hay indentación específica, devolver el texto original
  if not indent or indent == "" then
    return text
  end

  -- Aplicar indentación a cada línea
  local lines = vim.split(text, "\n")
  for i, line in ipairs(lines) do
    if line ~= "" then
      lines[i] = indent .. line
    end
  end

  return table.concat(lines, "\n")
end

-- Compara parámetros de función entre documentación y código
-- @param doc_params tabla: Parámetros extraídos de la documentación
-- @param code_params tabla: Parámetros extraídos del código
-- @return boolean: true si hay diferencias, false en caso contrario
function M.compare_parameters(doc_params, code_params)
  if not doc_params or not code_params then
    return true  -- Si alguno es nil, consideramos que hay diferencias
  end

  -- Verificar si la cantidad de parámetros es diferente
  if #doc_params ~= #code_params then
    return true
  end

  -- Verificar cada parámetro
  local doc_param_names = {}
  for _, param in ipairs(doc_params) do
    doc_param_names[param.name] = true
  end

  -- Comprobar que todos los parámetros del código estén documentados
  for _, param in ipairs(code_params) do
    if not doc_param_names[param.name] then
      return true  -- Encontrado un parámetro no documentado
    end
  end

  return false
end

-- Analiza cambios entre dos versiones de una función
-- @param old_content string: Contenido original de la función
-- @param new_content string: Contenido nuevo de la función
-- @return tabla: Información sobre los cambios detectados
function M.analyze_function_changes(old_content, new_content)
  if not old_content or not new_content then
    return { changed = true }
  end

  local changes = {
    changed = old_content ~= new_content,
    params_changed = false,
    return_changed = false,
    logic_changed = false
  }

  -- Implementación básica, los manejadores específicos de lenguaje
  -- proporcionarán análisis más detallados

  return changes
end

-- Valida que una respuesta de documentación cumpla con los requisitos mínimos
-- @param doc_block string: Bloque de documentación
-- @param filetype string: Tipo de archivo
-- @return boolean: true si la documentación es válida, false en caso contrario
function M.validate_documentation(doc_block, filetype)
  if not doc_block or doc_block == "" then
    return false
  end

  -- Reglas básicas de validación
  -- Debe tener al menos una línea no vacía
  local non_empty = false
  for line in doc_block:gmatch("[^\r\n]+") do
    if line:match("%S") then
      non_empty = true
      break
    end
  end

  if not non_empty then
    return false
  end

  -- Comprobar posible código en lugar de documentación
  local code_indicators = {
    "function ",
    "local function",
    "return ",
    "if ",
    "for ",
    "while ",
    "repeat ",
    "end)",
    "table.insert",
    "require(",
    "import ",
    "from ",
    "def ",
    "class ",
    "var ",
    "const ",
    "let "
  }

  for _, indicator in ipairs(code_indicators) do
    if doc_block:match(indicator) then
      -- Contar ocurrencias de este indicador
      local count = 0
      for _ in doc_block:gmatch(indicator) do
        count = count + 1
      end

      -- Si hay más de 2 ocurrencias, probablemente es código y no documentación
      if count > 2 then
        log.warn("Posible código detectado en lugar de documentación")
        return false
      end
    end
  end

  -- Verificar que contiene patrones típicos de documentación
  local doc_patterns = {
    "@param", "@return", "@throws", "@example",
    "Parameters:", "Returns:", "Throws:", "Examples:",
    "Description:", "Usage:", "Note:"
  }

  local contains_doc_pattern = false
  for _, pattern in ipairs(doc_patterns) do
    if doc_block:match(pattern) then
      contains_doc_pattern = true
      break
    end
  end

  -- Si no contiene ninguno de los patrones típicos pero es largo, verificar si parece código
  if not contains_doc_pattern and #doc_block > 200 then
    -- Contar líneas que parecen código vs. documentación
    local code_lines = 0
    local comment_lines = 0
    local total_lines = 0

    for line in doc_block:gmatch("[^\r\n]+") do
      if line:match("%S") then
        total_lines = total_lines + 1

        if line:match("^%s*%-%-") or line:match("^%s*#") or line:match("^%s*//") then
          comment_lines = comment_lines + 1
        elseif line:match("function") or line:match("return") or line:match("local") or
               line:match("if") or line:match("for") or line:match("while") then
          code_lines = code_lines + 1
        end
      end
    end

    -- Si hay más líneas de código que de comentarios y hay suficientes líneas...
    if code_lines > comment_lines and total_lines > 5 then
      log.warn("El bloque contiene más código que documentación: " .. code_lines .. " vs " .. comment_lines)
      return false
    end
  end

  -- Validaciones específicas del lenguaje
  local handler = require("copilotchatassist.documentation.detector")._get_language_handler(filetype)
  if handler and handler.validate_documentation then
    return handler.validate_documentation(doc_block)
  end

  return true
end

return M