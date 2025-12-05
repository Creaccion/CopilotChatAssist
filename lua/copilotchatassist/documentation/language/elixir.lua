-- Manejador específico para documentación de Elixir
-- Extiende el manejador común con funcionalidades específicas para Elixir

local M = {}
local common = require("copilotchatassist.documentation.language.common")
local log = require("copilotchatassist.utils.log")

-- Heredar funcionalidad básica del manejador común
for k, v in pairs(common) do
  M[k] = v
end

-- Configuración para el manejador de Elixir
M.config = {
  -- Opciones específicas para Elixir
  module_doc_style = "heredoc",  -- Estilo de documentación de módulos: "heredoc" (@moduledoc """...""") o "string" (@moduledoc "...")
  prefer_module_docs = true,     -- Dar prioridad a la documentación de módulos
  module_doc_spacing = 0,        -- Espacios adicionales después de @moduledoc
  safe_mode = true,             -- Modo seguro para evitar pérdida de código
  auto_detect_style = true,     -- Detectar automáticamente el estilo de documentación usado en el proyecto
}

-- Sobreescribir patrones para adaptarlos a Elixir
M.patterns = {
  -- Patrones específicos para Elixir
  module_start = "^%s*defmodule%s+([%w_%.]+)%s+do",
  function_start = "^%s*def%s+([%w_?!]+)%s*%(?(.-)%)?%s*do",
  private_function_start = "^%s*defp%s+([%w_?!]+)%s*%(?(.-)%)?%s*do",
  macro_start = "^%s*defmacro%s+([%w_?!]+)%s*%(?(.-)%)?%s*do",
  private_macro_start = "^%s*defmacrop%s+([%w_?!]+)%s*%(?(.-)%)?%s*do",
  guard_start = "^%s*defguard%s+([%w_?!]+)%s*%(?(.-)%)?%s*do",
  private_guard_start = "^%s*defguardp%s+([%w_?!]+)%s*%(?(.-)%)?%s*do",
  when_clause = "%s+when%s+.+",  -- Para eliminar cláusulas when en parámetros
  function_one_liner = "^%s*def%s+([%w_?!]+)%s*%(?(.-)%)?%s*,?%s*do:%s*(.+)",
  private_function_one_liner = "^%s*defp%s+([%w_?!]+)%s*%(?(.-)%)?%s*,?%s*do:%s*(.+)",
  comment_start = "^%s*#%s*",
  module_doc_start = "^%s*@moduledoc%s*(?:%s*\"\"\"|%s*''')%s*$",
  module_doc_end = "^%s*(?:\"\"\"|''')%s*$",
  module_doc_string = "^%s*@moduledoc%s+\"(.-)\"$",  -- @moduledoc "texto" en una línea
  function_doc_start = "^%s*@doc%s*(?:%s*\"\"\"|%s*''')%s*$",
  function_doc_end = "^%s*(?:\"\"\"|''')%s*$",
  function_doc_string = "^%s*@doc%s+\"(.-)\"$",  -- @doc "texto" en una línea
  type_spec = "^%s*@(?:spec|type|typep|callback|macrocallback)%s+",
  attribute = "^%s*@[%w_]+",
}

-- Encuentra la línea de finalización de una función o módulo en Elixir
-- @param lines tabla: Líneas del buffer
-- @param start_line número: Línea de inicio
-- @param item_type string: Tipo de elemento ("function", "module", etc)
-- @return número: Número de línea final o nil si no se puede determinar
function M.find_end_line(lines, start_line, item_type)
  if not lines or not start_line or start_line > #lines then
    return nil
  end

  -- Verificar si es una definición de una línea
  local line = lines[start_line]
  if line:match("^%s*def[p]?%s+[%w_?!]+%s*%(?.-%)?,?%s*do:%s*.+$") then
    return start_line  -- La función está definida en una línea
  end

  local depth = 1  -- Ya estamos dentro de un bloque 'do'

  -- En Elixir, buscamos la palabra clave "end" al mismo nivel de anidamiento
  for i = start_line + 1, #lines do
    local line = lines[i]

    -- Saltarse líneas de comentario
    if line:match("^%s*#") then
      goto continue
    end

    -- Contar bloques 'do' y 'end' para mantener el nivel de anidamiento
    local do_count = 0
    local end_count = 0

    -- Contar apariciones de 'do' en la línea
    for _ in line:gmatch("do%s*$") do
      do_count = do_count + 1
    end
    for _ in line:gmatch("do:") do
      do_count = do_count + 1
    end

    -- Contar apariciones de 'end' en la línea
    for _ in line:gmatch("end") do
      end_count = end_count + 1
    end

    -- Actualizar profundidad
    depth = depth + do_count - end_count

    -- Si llegamos a cero, encontramos el final del bloque
    if depth == 0 then
      return i
    end

    ::continue::
  end

  return #lines  -- Si no se puede determinar, devolver la última línea
end

-- Busca documentación en líneas de texto para Elixir
-- @param lines tabla: Líneas de texto a analizar
-- @param start_idx número: Índice de inicio para la búsqueda
-- @param max_lines número: Máximo de líneas a buscar hacia atrás
-- @return tabla: Información de la documentación o nil si no se encuentra
function M.find_doc_block(lines, start_idx, max_lines)
  if not lines or not start_idx or start_idx < 1 or #lines < start_idx then
    return nil
  end

  max_lines = max_lines or 20
  local min_idx = math.max(1, start_idx - max_lines)

  -- Buscar documentación antes de la definición (annotations @doc o comentarios #)
  local doc_end = start_idx - 1
  local doc_start = nil
  local in_doc_block = false
  local doc_block_start_pattern = nil
  local doc_block_end_pattern = nil
  local doc_lines = {}

  for i = doc_end, min_idx, -1 do
    local line = lines[i]

    -- Saltarse líneas vacías inmediatas
    if not doc_start and line:match("^%s*$") then
      doc_end = i - 1
      goto continue
    end

    -- Detectar diferentes tipos de documentación en Elixir
    local is_comment_line = line:match(M.patterns.comment_start)
    local is_module_doc_start = line:match(M.patterns.module_doc_start)
    local is_function_doc_start = line:match(M.patterns.function_doc_start)
    local is_doc_end = line:match(M.patterns.module_doc_end) or line:match(M.patterns.function_doc_end)
    local is_attribute = line:match(M.patterns.attribute)
    local is_type_spec = line:match(M.patterns.type_spec)

    -- Manejar bloques @doc y @moduledoc
    if is_doc_end and in_doc_block then
      table.insert(doc_lines, 1, line)
      in_doc_block = false
      if not doc_start then
        doc_start = i
      end
    elseif in_doc_block then
      table.insert(doc_lines, 1, line)
      if not doc_start then
        doc_start = i
      end
    elseif is_module_doc_start or is_function_doc_start then
      in_doc_block = true
      table.insert(doc_lines, 1, line)
      if not doc_start then
        doc_start = i
      end
    elseif is_comment_line then
      -- Agregar comentarios regulares
      table.insert(doc_lines, 1, line)
      if not doc_start then
        doc_start = i
      end
    elseif is_type_spec then
      -- Los @spec son parte de la documentación
      table.insert(doc_lines, 1, line)
      if not doc_start then
        doc_start = i
      end
    elseif is_attribute and not is_type_spec then
      -- Otros atributos no son parte de la documentación, terminamos
      break
    elseif line:match("%S") then
      -- Si encontramos una línea no vacía que no es documentación, terminamos
      break
    end

    ::continue::
  end

  if not doc_start or #doc_lines == 0 then
    return nil
  end

  return {
    start_line = doc_start,
    end_line = doc_end,
    lines = doc_lines,
    text = table.concat(doc_lines, "\n")
  }
end

-- Escanea un buffer en busca de problemas de documentación en Elixir
-- @param buffer número: ID del buffer a escanear
-- @return tabla: Lista de elementos con problemas de documentación
function M.scan_buffer(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local items = {}
  local issue_types = require("copilotchatassist.documentation.detector").ISSUE_TYPES

  -- Hacer un primer escaneo para encontrar el módulo principal y su contexto
  local main_module = nil
  local module_context = {}

  for i, line in ipairs(lines) do
    if line:match("^%s*defmodule%s+") then
      -- Mejorar la detección de nombres de módulos para manejar todos los formatos
      -- como IrSchedulesFacadeWeb.CustomShiftsController
      local module_name = line:match("defmodule%s+([%w_%.]+)")

      -- En caso de que el patrón anterior no funcione, intentar con uno más general
      if not module_name then
        -- Extraer todo entre 'defmodule' y 'do'
        module_name = line:match("defmodule%s+([^%s]+)%s+do")
        -- Si aún no se encuentra, intentar extraer cualquier texto antes de "do"
        if not module_name then
          module_name = line:match("defmodule(.-)%s+do")
          if module_name then
            module_name = module_name:gsub("%s+", "")
          end
        end
      end

      if module_name then
        log.debug("Módulo principal detectado: " .. module_name .. " en línea " .. i)
        main_module = {
          name = module_name,
          line = i,
          end_line = nil
        }

        -- Buscar el final del módulo
        local depth = 1
        for j = i + 1, #lines do
          local check_line = lines[j]
          if check_line:match("^%s*defmodule%s+") then
            depth = depth + 1
          elseif check_line:match("^%s*end%s*$") then
            depth = depth - 1
            if depth == 0 then
              main_module.end_line = j
              break
            end
          end
        end

        -- Capturar contexto del módulo
        if main_module.end_line then
          for j = i, main_module.end_line do
            table.insert(module_context, lines[j])
          end
        end

        break  -- Solo consideramos el primer módulo principal
      end
    end
  end

  -- Si encontramos un módulo principal, añadirlo a la lista de items
  if main_module and main_module.name then
    local module_line = main_module.line

    -- Verificar si tiene documentación
    local doc_info = M.find_doc_block(lines, module_line)
    local has_doc = doc_info ~= nil

    -- Si no tiene documentación o está incompleta, añadir a la lista
    if not has_doc then
      table.insert(items, {
        name = main_module.name,
        type = "module",
        bufnr = buffer,
        start_line = module_line,
        end_line = main_module.end_line or (module_line + 20),
        content = table.concat(module_context or {}, "\n"),
        has_doc = false,
        issue_type = issue_types.MISSING,
        params = {}
      })
      log.debug("Módulo " .. main_module.name .. " añadido a la lista para documentación")
    elseif has_doc then
      -- Comprobar si la documentación está desactualizada o incompleta
      local is_outdated = M.is_documentation_outdated(buffer, doc_info.lines, module_context)
      if is_outdated then
        table.insert(items, {
          name = main_module.name,
          type = "module",
          bufnr = buffer,
          start_line = module_line,
          end_line = main_module.end_line or (module_line + 20),
          content = table.concat(module_context or {}, "\n"),
          has_doc = true,
          issue_type = issue_types.OUTDATED,
          doc_start_line = doc_info.start_line,
          doc_end_line = doc_info.end_line,
          doc_lines = doc_info.lines,
          params = {}
        })
        log.debug("Módulo " .. main_module.name .. " tiene documentación desactualizada")
      end
    end
  end

  -- Buscar definiciones de módulos y funciones en Elixir
  for i, line in ipairs(lines) do
    -- Omitir líneas de comentario en esta fase
    if line:match("^%s*#") then
      goto continue
    end

    -- Variables para almacenar el nombre y tipo del elemento
    local item_name = nil
    local item_type = nil
    local params = nil

    -- Módulos
    -- Intentar los mismos patrones mejorados que se usan en la primera fase
    local module_name = nil
    if line:match("^%s*defmodule%s+") then
      module_name = line:match("defmodule%s+([%w_%.]+)")
      if not module_name then
        module_name = line:match("defmodule%s+([^%s]+)%s+do")
        if not module_name then
          module_name = line:match("defmodule(.-)%s+do")
          if module_name then
            module_name = module_name:gsub("%s+", "")
          end
        end
      end
    else
      module_name = line:match(M.patterns.module_start)
    end

    if module_name then
      item_name = module_name
      item_type = "module"
      log.debug("Detectado módulo adicional: " .. module_name)
    end

    -- Funciones públicas
    if not item_name then
      local func_name, func_params = line:match(M.patterns.function_start)
      if func_name then
        item_name = func_name
        item_type = "function"
        params = func_params
      end
    end

    -- Funciones privadas (defp)
    if not item_name then
      local private_func_name, private_func_params = line:match(M.patterns.private_function_start)
      if private_func_name then
        item_name = private_func_name
        item_type = "private_function"
        params = private_func_params
      end
    end

    -- Macros
    if not item_name then
      local macro_name, macro_params = line:match(M.patterns.macro_start)
      if macro_name then
        item_name = macro_name
        item_type = "macro"
        params = macro_params
      end
    end

    -- Macros privadas
    if not item_name then
      local private_macro_name, private_macro_params = line:match(M.patterns.private_macro_start)
      if private_macro_name then
        item_name = private_macro_name
        item_type = "private_macro"
        params = private_macro_params
      end
    end

    -- Guardas (defguard)
    if not item_name then
      local guard_name, guard_params = line:match(M.patterns.guard_start)
      if guard_name then
        item_name = guard_name
        item_type = "guard"
        params = guard_params
      end
    end

    -- Guardas privadas (defguardp)
    if not item_name then
      local private_guard_name, private_guard_params = line:match(M.patterns.private_guard_start)
      if private_guard_name then
        item_name = private_guard_name
        item_type = "private_guard"
        params = private_guard_params
      end
    end

    -- Funciones de una línea
    if not item_name then
      local oneliner_name, oneliner_params = line:match(M.patterns.function_one_liner)
      if oneliner_name then
        item_name = oneliner_name
        item_type = "function_oneliner"
        params = oneliner_params
      end
    end

    -- Funciones privadas de una línea
    if not item_name then
      local private_oneliner_name, private_oneliner_params = line:match(M.patterns.private_function_one_liner)
      if private_oneliner_name then
        item_name = private_oneliner_name
        item_type = "private_function_oneliner"
        params = private_oneliner_params
      end
    end

    -- Si se encontró un elemento documentable, procesarlo
    if item_name then
      log.debug("Elemento detectado: " .. item_name .. " (" .. item_type .. ") en línea " .. i)

      -- Encontrar el final del elemento
      local end_line = M.find_end_line(lines, i, item_type)
      if not end_line then
        -- Si no se puede determinar el final, usar una estimación
        end_line = i + 10  -- Asumimos que el elemento tiene al menos 10 líneas
      end

      -- Verificar si tiene documentación
      local doc_info = M.find_doc_block(lines, i)
      local has_doc = doc_info ~= nil

      -- Extraer parámetros para funciones y macros
      local param_names = {}
      if params and params ~= "" then
        -- Eliminar cláusulas 'when'
        params = params:gsub(M.patterns.when_clause, "")

        -- Extraer nombres de parámetros
        for param in params:gmatch("([^,]+)") do
          local param_name = param:match("^%s*([%w_@]+)%s*$") or  -- Parámetro simple
                             param:match("^%s*([%w_@]+)%s*[=:]")   -- Parámetro con valor por defecto
          if param_name then
            if param_name ~= "_" then  -- Ignorar parámetros anónimos
              table.insert(param_names, param_name)
            end
          end
        end
      end

      -- Contenido del elemento
      local content_lines = {}
      for j = i, end_line do
        table.insert(content_lines, lines[j])
      end
      local content = table.concat(content_lines, "\n")

      -- Determinar tipo de problema
      local issue_type = nil
      if not has_doc and (item_type:match("^private_") == nil) then
        -- Solo considerar funciones públicas como que necesitan documentación
        issue_type = issue_types.MISSING
      elseif has_doc then
        -- Verificar si la documentación está incompleta (solo para elementos públicos)
        if not item_type:match("^private_") then
          local is_incomplete = M.is_documentation_incomplete(buffer, doc_info.lines, param_names)
          if is_incomplete then
            issue_type = issue_types.INCOMPLETE
          else
            local is_outdated = M.is_documentation_outdated(buffer, doc_info.lines, content_lines)
            if is_outdated then
              issue_type = issue_types.OUTDATED
            end
          end
        end
      end

      -- Si hay un problema, agregar a la lista
      if issue_type then
        table.insert(items, {
          name = item_name,
          type = item_type,
          bufnr = buffer,
          start_line = i,
          end_line = end_line,
          content = content,
          has_doc = has_doc,
          issue_type = issue_type,
          doc_start_line = has_doc and doc_info.start_line or nil,
          doc_end_line = has_doc and doc_info.end_line or nil,
          doc_lines = has_doc and doc_info.lines or nil,
          params = param_names
        })
      end
    end

    ::continue::
  end

  log.debug("Se encontraron " .. #items .. " elementos con problemas de documentación en el archivo Elixir")
  return items
end

-- Determina si la documentación está incompleta en Elixir
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param param_names tabla: Nombres de los parámetros
-- @return boolean: true si está incompleta, false en caso contrario
function M.is_documentation_incomplete(buffer, doc_lines, param_names)
  if not doc_lines or not param_names or #param_names == 0 then
    return false
  end

  local doc_text = table.concat(doc_lines, "\n")

  -- Elixir no tiene un formato estándar para documentar parámetros como @param,
  -- pero podemos buscar si los parámetros están mencionados en la documentación
  for _, param in ipairs(param_names) do
    if param ~= "" and not param:match("^_") then  -- Ignorar parámetros anónimos
      -- Buscar menciones del parámetro (con backticks o sin ellos)
      local param_pattern = "`" .. param .. "`" .. "[%s%p]" -- Con backticks
      local param_pattern_alt = "[%s%p]" .. param .. "[%s%p]" -- Sin backticks

      if not doc_text:match(param_pattern) and not doc_text:match(param_pattern_alt) then
        return true  -- Parámetro no documentado
      end
    end
  end

  return false
end

-- Determina si la documentación está desactualizada en Elixir
-- @param buffer número: ID del buffer
-- @param doc_lines tabla: Líneas de documentación
-- @param element_lines tabla: Líneas del elemento
-- @return boolean: true si está desactualizada, false en caso contrario
function M.is_documentation_outdated(buffer, doc_lines, element_lines)
  -- Implementación básica: verificar si hay documentación de parámetros que ya no existen
  if not doc_lines or not element_lines then
    return false
  end

  local doc_text = table.concat(doc_lines, "\n")
  local element_text = table.concat(element_lines, "\n")

  -- Buscar @spec para verificar si coincide con la implementación
  local spec_line = nil
  for _, line in ipairs(doc_lines) do
    if line:match("^%s*@spec") then
      spec_line = line
      break
    end
  end

  if spec_line then
    -- Extraer tipos de parámetros del @spec
    local spec_params = spec_line:match("@spec[^%(]+%((.-)%)")
    if spec_params then
      -- Extraer parámetros reales de la función
      local func_params = element_lines[1]:match("def[p]?[^%(]+%((.-)%)")
      if func_params then
        -- Contar número de parámetros
        local spec_param_count = 0
        for _ in spec_params:gmatch(",") do
          spec_param_count = spec_param_count + 1
        end
        spec_param_count = spec_param_count + 1  -- Añadir uno más para el último parámetro

        local func_param_count = 0
        for _ in func_params:gmatch(",") do
          func_param_count = func_param_count + 1
        end
        func_param_count = func_param_count + 1  -- Añadir uno más para el último parámetro

        -- Si el número de parámetros no coincide, la documentación está desactualizada
        if spec_param_count ~= func_param_count and func_params ~= "" then
          return true
        end
      end
    end
  end

  return false
end

-- Normaliza la documentación para Elixir
-- @param doc_block string: Bloque de documentación
-- @return string: Documentación normalizada
function M.normalize_documentation(doc_block)
  if not doc_block or doc_block == "" then
    return ""
  end

  -- Eliminar líneas vacías al inicio y al final
  doc_block = doc_block:gsub("^%s*(.-)%s*$", "%1")

  -- Asegurar que la documentación tenga el formato correcto para Elixir
  local lines = vim.split(doc_block, "\n")
  local normalized_lines = {}

  -- Determinar si ya es un bloque @doc o @moduledoc
  local is_doc_block = false
  for _, line in ipairs(lines) do
    if line:match("^%s*@doc%s") or line:match("^%s*@moduledoc%s") then
      is_doc_block = true
      break
    end
  end

  -- Si ya es un bloque @doc o tiene formato adecuado, usarlo como está
  if is_doc_block then
    return doc_block
  end

  -- Si son comentarios regulares, convertir a formato @doc
  if lines[1]:match("^%s*#") then
    -- Convertir comentarios # en un bloque @doc """
    table.insert(normalized_lines, "@doc \"\"\"")

    -- Filtrar secciones vacías (problemas de "Parameters", "Returns" y "Errors" vacías)
    local filtered_lines = {}
    local i = 1

    while i <= #lines do
      local line = lines[i]:gsub("^%s*#%s*", "")

      -- Verificar si es un encabezado de sección
      if line:match("^%s*[Pp]arameters%s*$") or
         line:match("^%s*[Rr]eturns%s*$") or
         line:match("^%s*[Ee]rrors%s*$") then

        -- Verificar si la sección está vacía
        local next_line_index = i + 1
        local is_empty_section = true

        -- Buscar contenido antes del siguiente encabezado
        while next_line_index <= #lines and
              not lines[next_line_index]:gsub("^%s*#%s*", ""):match("^%s*[A-Z][a-z]+%s*$") do
          local next_content = lines[next_line_index]:gsub("^%s*#%s*", "")
          if next_content:match("[%w%p]") and not next_content:match("^%s*$") then
            is_empty_section = false
            break
          end
          next_line_index = next_line_index + 1
        end

        -- Si la sección no está vacía, incluir el encabezado
        if not is_empty_section then
          table.insert(filtered_lines, line)
        end
      else
        -- No es un encabezado, incluir la línea
        table.insert(filtered_lines, line)
      end

      i = i + 1
    end

    -- Usar las líneas filtradas
    for _, line in ipairs(filtered_lines) do
      table.insert(normalized_lines, line)
    end

    table.insert(normalized_lines, "\"\"\"")
  else
    -- Si no tiene formato reconocible, crear un bloque @doc
    table.insert(normalized_lines, "@doc \"\"\"")
    for _, line in ipairs(lines) do
      table.insert(normalized_lines, line)
    end
    table.insert(normalized_lines, "\"\"\"")
  end

  return table.concat(normalized_lines, "\n")
end

-- Aplica documentación a un elemento en Elixir
-- @param buffer número: ID del buffer
-- @param start_line número: Línea antes de la cual insertar la documentación
-- @param doc_block string: Bloque de documentación a insertar
-- @return boolean: true si se aplicó correctamente, false en caso contrario
function M.apply_documentation(buffer, start_line, doc_block, item)
  if not doc_block or doc_block == "" then
    log.error("Bloque de documentación vacío")
    return false
  end

  -- Asegurar que la documentación esté en formato Elixir
  doc_block = M.normalize_documentation(doc_block)

  -- Convertir a líneas
  local doc_lines = vim.split(doc_block, "\n")

  -- Verificaciones de seguridad
  if not vim.api.nvim_buf_is_valid(buffer) then
    log.error("Buffer inválido al aplicar documentación")
    return false
  end

  -- Verificar que start_line está dentro del rango del buffer
  local buffer_line_count = vim.api.nvim_buf_line_count(buffer)
  if start_line <= 0 or start_line > buffer_line_count + 1 then
    log.error("Línea de inicio fuera de rango: " .. start_line .. " (total líneas: " .. buffer_line_count .. ")")
    return false
  end

  -- Obtener la línea de destino para la indentación y verificar que sea código válido
  local target_line = ""
  if start_line <= buffer_line_count then
    local lines = vim.api.nvim_buf_get_lines(buffer, start_line - 1, start_line, false)
    target_line = lines[1] or ""

    -- Verificar que la línea de destino contiene código real (no solo comentarios o espacios)
    if target_line:match("^%s*$") or target_line:match("^%s*#") then
      log.warn("La línea de destino parece vacía o un comentario. Verificando contexto...")

      -- Verificar las siguientes líneas para asegurarse de que estamos antes de código real
      local found_code = false
      for i = start_line, math.min(start_line + 5, buffer_line_count) do
        local check_line = vim.api.nvim_buf_get_lines(buffer, i - 1, i, false)[1] or ""
        if check_line:match("%S") and not check_line:match("^%s*#") then
          found_code = true
          break
        end
      end

      if not found_code then
        log.error("No se encontró código válido después de la línea de destino. Posible posición incorrecta.")
        return false
      end
    end
  end

  -- Verificar si ya existe documentación para evitar duplicación
  local existing_doc = false
  local is_module = false
  local is_module_at_start = false

  -- Comprobar si estamos documentando un módulo
  if target_line:match("defmodule") then
    is_module = true
    if start_line <= 5 then  -- Si el módulo está cerca del inicio del archivo
      is_module_at_start = true
      log.debug("Detectada documentación de módulo al inicio del archivo")
    end
  end

  -- Buscar documentación existente para evitar duplicaciones
  local buffer_content = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local doc_positions = {}

  -- Buscar declaración de módulo
  local module_start_line = nil
  for i, line in ipairs(buffer_content) do
    if line:match("defmodule") then
      module_start_line = i
      break
    end
  end

  -- Buscar todas las anotaciones @moduledoc y @doc
  for i, line in ipairs(buffer_content) do
    if line:match("^%s*@moduledoc") or line:match("^%s*@doc") then
      table.insert(doc_positions, i)

      -- Verificar si es un @doc fuera de un módulo
      if line:match("^%s*@doc") and module_start_line and i < module_start_line then
        log.warn("Detectada anotación @doc antes de la definición del módulo. Corrigiendo posición.")
        -- Eliminar la documentación mal ubicada
        local doc_end = i
        if line:match('"""') then
          -- Es un bloque heredoc
          for j = i + 1, math.min(i + 30, #buffer_content) do
            if buffer_content[j]:match('"""') then
              doc_end = j
              break
            end
          end
        end
        vim.api.nvim_buf_set_lines(buffer, i - 1, doc_end, false, {})
        log.info("Eliminada documentación fuera del módulo en líneas " .. i .. "-" .. doc_end)

        -- Ajustar línea de inicio
        start_line = module_start_line
        log.info("Ajustada posición de documentación a línea " .. module_start_line)
      end

      -- Si encontramos documentación existente cerca de la posición actual
      if math.abs(i - start_line) < 10 then
        existing_doc = true
        log.warn("Se encontró documentación existente en línea " .. i .. ", cerca de la posición actual")

        -- Si esta documentación está dentro de un módulo que estamos documentando, eliminarla
        if is_module and line:match("^%s*@moduledoc") then
          -- Buscar el final de la documentación
          local doc_end = i
          if line:match('"""') then
            -- Es un bloque heredoc
            for j = i + 1, math.min(i + 30, #buffer_content) do
              if buffer_content[j]:match('"""') then
                doc_end = j
                break
              end
            end
          end

          -- Eliminar la documentación existente
          vim.api.nvim_buf_set_lines(buffer, i - 1, doc_end, false, {})
          log.info("Eliminada documentación existente en líneas " .. i .. "-" .. doc_end)

          -- Ajustar línea de inicio para la nueva documentación
          if start_line > i then
            start_line = start_line - (doc_end - i + 1)
            if start_line < 1 then start_line = 1 end
          end

          break
        end
      end
    end
  end

  local indent = target_line:match("^(%s*)")

  -- Aplicar indentación a las líneas de documentación
  for i, line in ipairs(doc_lines) do
    if line ~= "" then
      doc_lines[i] = indent .. line
    end
  end

  log.debug("Insertando documentación de " .. #doc_lines .. " líneas antes de la línea " .. start_line)

  -- Guardar la línea de destino para verificar después
  local target_line_content = target_line

  -- Crear una copia de seguridad de las líneas circundantes
  local backup_start = math.max(1, start_line - 5)
  local backup_end = math.min(buffer_line_count, start_line + 5)
  local backup_lines = vim.api.nvim_buf_get_lines(buffer, backup_start - 1, backup_end, false)
  local backup_info = {
    start_line = backup_start,
    end_line = backup_end,
    lines = backup_lines
  }

  -- Insertar la documentación (añadir línea en blanco al final si no existe)
  if #doc_lines > 0 and doc_lines[#doc_lines] ~= "" and not is_module_at_start then
    table.insert(doc_lines, "")  -- Añadir línea en blanco para separar de la función
  end

  -- Tratar documentación de módulos de manera especial
  if is_module and start_line <= 5 then
    -- Para módulos al inicio del archivo, asegurar que la documentación está correctamente colocada
    -- Primero, encontrar la línea de definición del módulo
    local module_line = nil
    for i, line in ipairs(buffer_content) do
      if line:match("defmodule") then
        module_line = i
        break
      end
    end

    if module_line and module_line > 1 then
      -- Colocar la documentación justo antes de la definición del módulo
      start_line = module_line
    end
  end

  -- Insertar la documentación sin reemplazar nada (modo seguro)
  vim.api.nvim_buf_set_lines(buffer, start_line - 1, start_line - 1, false, doc_lines)

  -- Verificar que la línea de destino sigue siendo la misma (no se borró código)
  if start_line <= buffer_line_count then
    local new_line_index = start_line + #doc_lines - 1
    if new_line_index <= vim.api.nvim_buf_line_count(buffer) then
      local new_target_line = vim.api.nvim_buf_get_lines(buffer, new_line_index - 1, new_line_index, false)[1] or ""

      -- Para módulos Elixir, permitir cambios en la línea de destino
      if new_target_line ~= target_line_content and target_line_content:match("%S") then
        log.warn("La línea de destino ha cambiado después de la inserción.")
        log.debug("Original: '" .. target_line_content .. "'")
        log.debug("Nueva: '" .. new_target_line .. "'")

        -- Verificar si estamos ante un módulo Elixir (más tolerante con cambios)
        local is_elixir_module = target_line_content:match("defmodule") ~= nil

        -- Para módulos Elixir, verificar que la definición del módulo sigue presente
        if is_elixir_module then
          -- Buscar la definición del módulo en todo el archivo
          local found_module_def = false
          local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
          local module_name = target_line_content:match("defmodule%s+([%w_.]+)") or ""

          for i, line in ipairs(buffer_lines) do
            if line:match("defmodule%s+" .. module_name) then
              found_module_def = true
              log.info("Definición del módulo " .. module_name .. " encontrada en línea " .. i)
              break
            end
          end

          if found_module_def then
            log.info("La definición del módulo se ha movido pero sigue presente. Esto es normal en Elixir.")

            -- Verificar si hay documentación duplicada
            local doc_count = 0
            for _, line in ipairs(buffer_lines) do
              if line:match("^%s*@moduledoc") then
                doc_count = doc_count + 1
              end
            end

            if doc_count > 1 then
              log.warn("Se han detectado " .. doc_count .. " anotaciones @moduledoc. Puede haber documentación duplicada.")
            end

            return true
          end
        end

        -- Verificar si el código ha sido modificado pero aún contiene la definición clave
        if target_line_content:match("defmodule") and new_target_line:match("defmodule") then
          log.info("La línea ha cambiado pero mantiene la definición del módulo. Esto es aceptable.")
          return true
        elseif target_line_content:match("def%s+[%w_?!]+") and new_target_line:match("def%s+[%w_?!]+") then
          log.info("La línea ha cambiado pero mantiene la definición de función. Esto es aceptable.")
          return true
        end

        -- Si parece que se eliminó código importante, restaurar el estado original
        if (target_line_content:match("[%w_]") and not new_target_line:match("[%w_]")) or
           (target_line_content:match("def") and not is_elixir_module) then
          log.warn("Detectada posible pérdida de código importante. Restaurando estado original...")

          -- Comprobar si todavía existe la definición en otro lugar antes de restaurar
          local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
          local key_pattern = target_line_content:match("def%s+[%w_?!]+") or target_line_content:match("defmodule%s+[%w_.]+")
          local still_exists = false

          if key_pattern then
            for _, line in ipairs(buffer_lines) do
              if line:match(key_pattern) then
                still_exists = true
                break
              end
            end
          end

          if not still_exists then
            vim.api.nvim_buf_set_lines(buffer, backup_info.start_line - 1, backup_info.start_line - 1 + #backup_info.lines, false, backup_info.lines)
            vim.notify("Se detectó un problema al insertar documentación. Se ha restaurado el estado anterior para evitar pérdida de código.", vim.log.levels.WARN)
            return false
          else
            log.info("A pesar de los cambios, la definición clave aún existe en el archivo. Se mantiene la documentación.")
            return true
          end
        end
      end
    else
      log.error("La posición esperada de la línea de destino está fuera del buffer después de la inserción")
    end
  end

  return true
end

-- Actualiza una documentación existente en Elixir
-- @param buffer número: ID del buffer
-- @param doc_start_line número: Línea de inicio de la documentación
-- @param doc_end_line número: Línea de fin de la documentación
-- @param doc_block string: Nuevo bloque de documentación
-- @return boolean: true si se actualizó correctamente, false en caso contrario
function M.update_documentation(buffer, doc_start_line, doc_end_line, doc_block)
  if not doc_block or doc_block == "" then
    log.error("Bloque de documentación vacío")
    return false
  end

  -- Verificaciones de seguridad
  if not vim.api.nvim_buf_is_valid(buffer) then
    log.error("Buffer inválido al actualizar documentación")
    return false
  end

  local buffer_line_count = vim.api.nvim_buf_line_count(buffer)

  -- Verificar que las líneas están dentro del rango del buffer
  if doc_start_line <= 0 or doc_start_line > buffer_line_count then
    log.error("Línea de inicio de documentación fuera de rango: " .. doc_start_line .. " (total líneas: " .. buffer_line_count .. ")")
    return false
  end

  if doc_end_line <= 0 or doc_end_line > buffer_line_count then
    log.error("Línea de fin de documentación fuera de rango: " .. doc_end_line .. " (total líneas: " .. buffer_line_count .. ")")
    return false
  end

  -- Verificar que doc_start_line <= doc_end_line
  if doc_start_line > doc_end_line then
    log.error("Línea de inicio (" .. doc_start_line .. ") posterior a línea de fin (" .. doc_end_line .. ")")
    return false
  end

  -- Guardar la línea siguiente a la documentación para verificar después
  local next_line_idx = doc_end_line
  local next_line = ""
  if next_line_idx <= buffer_line_count then
    next_line = vim.api.nvim_buf_get_lines(buffer, next_line_idx - 1, next_line_idx, false)[1] or ""
  end

  -- Verificar si la línea siguiente contiene código importante
  local contains_important_code = next_line:match("%S") and not next_line:match("^%s*#")
  local contains_elixir_def = next_line:match("def%s+") or next_line:match("defp%s+") or
                              next_line:match("defmodule%s+") or next_line:match("defmacro%s+")

  -- Capturar un contexto más amplio
  local context_start = math.max(1, doc_start_line - 3)
  local context_end = math.min(buffer_line_count, doc_end_line + 10)
  local context_lines = vim.api.nvim_buf_get_lines(buffer, context_start - 1, context_end, false)

  -- Asegurar que la documentación esté en formato Elixir
  doc_block = M.normalize_documentation(doc_block)

  -- Convertir a líneas
  local doc_lines = vim.split(doc_block, "\n")

  -- Obtener la indentación de la primera línea de la documentación existente
  local first_doc_line = vim.api.nvim_buf_get_lines(buffer, doc_start_line - 1, doc_start_line, false)[1] or ""
  local indent = first_doc_line:match("^(%s*)")

  -- Aplicar indentación a las líneas de documentación
  for i, line in ipairs(doc_lines) do
    if line ~= "" then
      doc_lines[i] = indent .. line
    end
  end

  log.debug("Actualizando documentación desde línea " .. doc_start_line .. " hasta " .. doc_end_line)

  -- Hacer una copia de seguridad de las líneas que se van a reemplazar y su entorno
  local backup_lines = vim.api.nvim_buf_get_lines(buffer, doc_start_line - 1, doc_end_line, false)

  -- También realizar una copia de seguridad del contexto amplio
  local full_backup_start = math.max(1, doc_start_line - 5)
  local full_backup_end = math.min(buffer_line_count, doc_end_line + 10)
  local full_backup_lines = vim.api.nvim_buf_get_lines(buffer, full_backup_start - 1, full_backup_end, false)
  local full_backup = {
    start_line = full_backup_start,
    end_line = full_backup_end,
    lines = full_backup_lines
  }

  -- Número de líneas en el bloque original de documentación
  local original_doc_lines_count = doc_end_line - doc_start_line + 1

  -- Verificar si estamos actualizando la documentación de un módulo
  local is_module_doc = false
  for _, line in ipairs(context_lines) do
    if line:match("@moduledoc") then
      is_module_doc = true
      break
    end
  end

  -- Detectar documentación de módulo al inicio del archivo
  local is_module_at_start = doc_start_line <= 3 and is_module_doc

  -- Comparar longitudes para anticipar problemas
  if math.abs(#doc_lines - original_doc_lines_count) > 10 then
    log.warn("La diferencia de tamaño entre documentación original y nueva es significativa: " ..
             original_doc_lines_count .. " vs " .. #doc_lines)

    -- Si la nueva documentación es mucho más corta, puede ser problemático
    if #doc_lines < original_doc_lines_count / 2 and original_doc_lines_count > 5 then
      log.warn("La nueva documentación es mucho más corta que la original. Verificando contenido...")
      -- Aquí podríamos implementar verificaciones adicionales de contenido
    end
  end

  -- Añadir línea en blanco al final si la documentación actual no termina con una
  -- Pero no para documentación de módulos al inicio del archivo
  if #doc_lines > 0 and doc_lines[#doc_lines] ~= "" and next_line ~= "" and not is_module_at_start then
    table.insert(doc_lines, "")
  end

  -- Reemplazar la documentación existente
  vim.api.nvim_buf_set_lines(buffer, doc_start_line - 1, doc_end_line, false, doc_lines)

  -- Verificar que la siguiente línea sigue siendo la misma (no se borró código)
  if next_line_idx <= buffer_line_count then
    -- Calcular el nuevo índice de la línea siguiente
    local new_next_line_idx = doc_start_line + #doc_lines - 1
    local current_next_line = ""
    if new_next_line_idx < vim.api.nvim_buf_line_count(buffer) then
      current_next_line = vim.api.nvim_buf_get_lines(buffer, new_next_line_idx, new_next_line_idx + 1, false)[1] or ""
    end

    -- Para módulos, buscamos la definición en las líneas siguientes
    if is_module_doc then
      local found_module_def = false
      for i = new_next_line_idx, math.min(new_next_line_idx + 10, vim.api.nvim_buf_line_count(buffer)) do
        local line = vim.api.nvim_buf_get_lines(buffer, i - 1, i, false)[1] or ""
        if line:match("defmodule") then
          found_module_def = true
          log.info("Encontrada definición de módulo después de la documentación")
          break
        end
      end

      -- Si es documentación de módulo y encontramos la definición, todo está bien
      if found_module_def then
        return true
      end
    end

    -- Si la línea siguiente cambió y contenía código importante, esto podría ser un problema
    if current_next_line ~= next_line and contains_important_code then
      log.warn("La línea siguiente a la documentación ha cambiado.")
      log.debug("Original: '" .. next_line .. "'")
      log.debug("Nueva: '" .. current_next_line .. "'")

      -- Si parece que se eliminó código importante, restaurar el estado original
      if (next_line:match("[%w_]") and not current_next_line:match("[%w_]")) or contains_elixir_def then
        log.warn("Detectada posible pérdida de código importante. Restaurando documentación original...")
        vim.api.nvim_buf_set_lines(buffer, doc_start_line - 1, doc_start_line - 1 + #doc_lines, false, backup_lines)
        vim.notify("Se detectó un problema al actualizar la documentación. Se ha restaurado la documentación original para evitar pérdida de código.", vim.log.levels.WARN)
        return false
      end
    end
  end

  -- Verificar la integridad del código después de la actualización
  local post_update_lines = vim.api.nvim_buf_get_lines(buffer, context_start - 1, context_end, false)
  local elixir_element_missing = false
  local elixir_elements = {}

  -- Primero, identificar todas las definiciones importantes en el contexto original
  for _, line in ipairs(context_lines) do
    local is_elixir_element = line:match("def%s+") or line:match("defp%s+") or
                              line:match("defmodule%s+") or line:match("defmacro%s+")
    if is_elixir_element and not line:match("^%s*#") then
      table.insert(elixir_elements, line)
    end
  end

  -- Implementar una verificación más flexible
  -- En lugar de exigir líneas exactamente iguales, buscar patrones de definición
  for _, element_line in ipairs(elixir_elements) do
    -- Extraer el nombre del elemento definido
    local element_name = element_line:match("def%s+([%w_!?]+)") or
                         element_line:match("defp%s+([%w_!?]+)") or
                         element_line:match("defmodule%s+([%w_.]+)") or
                         element_line:match("defmacro%s+([%w_!?]+)")

    if element_name then
      local found = false

      -- Buscar si el elemento sigue definido en el nuevo contexto
      for _, post_line in ipairs(post_update_lines) do
        if post_line:match(element_name) and (
           post_line:match("def%s+" .. element_name) or
           post_line:match("defp%s+" .. element_name) or
           post_line:match("defmodule%s+" .. element_name) or
           post_line:match("defmacro%s+" .. element_name)) then
          found = true
          break
        end
      end

      if not found then
        elixir_element_missing = true
        log.error("¡Detectada pérdida de definición de elemento Elixir! Elemento: '" .. element_name .. "'")
        break
      end
    end
  end

  -- Si hay inconsistencias graves, restaurar el estado completo
  if elixir_element_missing then
    log.warn("Detectada pérdida de definición de elemento Elixir. Restaurando estado original completo...")
    vim.api.nvim_buf_set_lines(buffer, full_backup.start_line - 1, full_backup.start_line - 1 + #full_backup.lines, false, full_backup.lines)
    vim.notify("Se detectó pérdida de código Elixir al actualizar la documentación. Se ha restaurado el estado original.", vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Configura el manejador específicamente para archivos Elixir
-- @param buffer número: ID del buffer a configurar
-- @return boolean: true si se configuró correctamente
function M.setup_for_elixir(buffer)
  -- Detectar el estilo de documentación usado en este archivo
  if M.config.auto_detect_style then
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, math.min(100, vim.api.nvim_buf_line_count(buffer)), false)
    local heredoc_count = 0
    local string_count = 0

    for _, line in ipairs(lines) do
      if line:match("@moduledoc%s*\"\"\"") or line:match("@doc%s*\"\"\"") then
        heredoc_count = heredoc_count + 1
      elseif line:match("@moduledoc%s+\".+\"") or line:match("@doc%s+\".+\"") then
        string_count = string_count + 1
      end
    end

    -- Determinar el estilo predominante
    if heredoc_count > 0 or string_count == 0 then
      M.config.module_doc_style = "heredoc"
    elseif string_count > heredoc_count then
      M.config.module_doc_style = "string"
    end

    log.debug("Detectado estilo de documentación Elixir: " .. M.config.module_doc_style)
  end

  -- Verificar si hay módulo al inicio del archivo para manejo especial
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, math.min(10, vim.api.nvim_buf_line_count(buffer)), false)
  local has_module_at_start = false

  for i, line in ipairs(lines) do
    if line:match("defmodule") then
      has_module_at_start = true
      M.config.module_start_line = i
      log.debug("Detectado módulo Elixir al inicio del archivo en línea " .. i)
      break
    end
  end

  if has_module_at_start then
    M.config.is_module_file = true
    M.config.safe_mode = true  -- Activar modo seguro para archivos con módulo al inicio
  end

  return true
end

-- Encuentra ejemplos de documentación en el buffer
-- @param buffer número: ID del buffer
-- @param max_examples número: Máximo número de ejemplos a encontrar
-- @return tabla: Lista de ejemplos de documentación encontrados
function M.find_documentation_examples(buffer, max_examples)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local examples = {}
  max_examples = max_examples or 3

  local i = 1
  while i <= #lines and #examples < max_examples do
    local line = lines[i]

    -- Buscar inicio de bloque @doc o @moduledoc
    if line:match("^%s*@doc%s*\"\"\"") or line:match("^%s*@moduledoc%s*\"\"\"") then
      local doc_start = i
      local doc_end = nil

      -- Buscar el final del bloque
      for j = i + 1, math.min(i + 30, #lines) do
        if lines[j]:match("^%s*\"\"\"") then
          doc_end = j
          break
        end
      end

      -- Si encontramos un bloque completo
      if doc_end and doc_end > doc_start then
        local doc_lines = {}
        for j = doc_start, doc_end do
          table.insert(doc_lines, lines[j])
        end

        -- Si tiene un formato detallado, es un buen ejemplo
        local doc_text = table.concat(doc_lines, "\n")
        if #doc_text > 50 then  -- Un tamaño mínimo para considerarlo útil
          table.insert(examples, doc_text)
        end

        i = doc_end + 1  -- Saltar al final del bloque
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end

  return examples
end

return M