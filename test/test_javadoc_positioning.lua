-- Test específico para verificar el correcto posicionamiento de JavaDoc
-- Este script detecta problemas comunes en la estructura de documentación JavaDoc

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

      -- Reconstruir el contenido del buffer con las nuevas líneas
      local new_content = {}
      -- Copiar líneas antes del cambio
      for i = 1, start do
        table.insert(new_content, mock.buffer_content[i])
      end
      -- Insertar las nuevas líneas
      for _, line in ipairs(lines) do
        table.insert(new_content, line)
      end
      -- Copiar líneas después del cambio
      for i = end_line + 1, #mock.buffer_content do
        table.insert(new_content, mock.buffer_content[i])
      end
      -- Actualizar el buffer
      mock.buffer_content = new_content
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
    end,
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

-- Mock de log con detalle
local log = {
  debug = function(msg)
    mock.log_messages = mock.log_messages or {}
    table.insert(mock.log_messages, { level = "debug", msg = msg })
    -- print("[DEBUG] " .. msg)
  end,
  info = function(msg)
    mock.log_messages = mock.log_messages or {}
    table.insert(mock.log_messages, { level = "info", msg = msg })
    -- print("[INFO] " .. msg)
  end,
  warn = function(msg)
    mock.log_messages = mock.log_messages or {}
    table.insert(mock.log_messages, { level = "warn", msg = msg })
    -- print("[WARN] " .. msg)
  end,
  error = function(msg)
    mock.log_messages = mock.log_messages or {}
    table.insert(mock.log_messages, { level = "error", msg = msg })
    -- print("[ERROR] " .. msg)
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

local detector = {
  _get_language_handler = function(filetype)
    if filetype == "java" then
      return require("copilotchatassist.documentation.language.java")
    else
      return require("copilotchatassist.documentation.language.elixir")
    end
  end,
  ISSUE_TYPES = {
    MISSING = "missing",
    OUTDATED = "outdated",
    INCOMPLETE = "incomplete"
  }
}
package.loaded["copilotchatassist.documentation.detector"] = detector

-- Mock para common
local common = {
  find_doc_block = function() return nil end,
  is_documentation_outdated = function() return false end,
  is_documentation_incomplete = function() return false end,
  normalize_documentation = function(doc) return doc end
}
package.loaded["copilotchatassist.documentation.language.common"] = common

-- Función para imprimir cabecera
local function print_header(text)
  print("\n" .. string.rep("=", 70))
  print("= " .. text)
  print(string.rep("=", 70))
end

-- Función para imprimir subencabezado
local function print_subheader(text)
  print("\n" .. string.rep("-", 50))
  print("- " .. text)
  print(string.rep("-", 50))
end

-- Función para analizar la estructura del archivo Java
local function analyze_java_structure(content)
  local structure = {
    package = nil,
    imports = {},
    javadocs = {},
    annotations = {},
    class_declaration = nil,
    methods = {},
    floating_comments = {}
  }

  -- Analizar línea por línea
  local i = 1
  while i <= #content do
    local line = content[i]

    -- Detectar package
    if line:match("^package%s+") then
      structure.package = {line = i, content = line}

    -- Detectar imports
    elseif line:match("^import%s+") then
      table.insert(structure.imports, {line = i, content = line})

    -- Detectar JavaDoc
    elseif line:match("^%s*/%*%*") then
      local javadoc_start = i
      local javadoc_content = {line}

      -- Buscar el fin del JavaDoc
      local j = i + 1
      while j <= #content and not content[j]:match("%*/") do
        table.insert(javadoc_content, content[j])
        j = j + 1
      end

      -- Si encontramos el cierre
      if j <= #content and content[j]:match("%*/") then
        table.insert(javadoc_content, content[j])

        -- Determinar a qué está asociado este JavaDoc
        local associated_element = nil
        local next_non_blank_line = j + 1

        -- Buscar la siguiente línea no vacía
        while next_non_blank_line <= #content and content[next_non_blank_line]:match("^%s*$") do
          next_non_blank_line = next_non_blank_line + 1
        end

        -- Determinar el tipo de elemento asociado
        if next_non_blank_line <= #content then
          local next_line = content[next_non_blank_line]

          -- Anotación
          if next_line:match("^%s*@[%w_]+") then
            associated_element = {type = "annotation", line = next_non_blank_line}

          -- Clase/Interfaz/Enum
          elseif next_line:match("^%s*public%s+class%s+") or
                 next_line:match("^%s*class%s+") or
                 next_line:match("^%s*public%s+interface%s+") or
                 next_line:match("^%s*interface%s+") or
                 next_line:match("^%s*public%s+enum%s+") or
                 next_line:match("^%s*enum%s+") then
            associated_element = {type = "class", line = next_non_blank_line}

          -- Método/Constructor
          elseif next_line:match("^%s*public%s+[%w_.<>]+%s+[%w_]+%s*%(") or
                 next_line:match("^%s*private%s+[%w_.<>]+%s+[%w_]+%s*%(") or
                 next_line:match("^%s*protected%s+[%w_.<>]+%s+[%w_]+%s*%(") then
            associated_element = {type = "method", line = next_non_blank_line}

          -- Sin asociación clara
          else
            associated_element = {type = "unknown", line = next_non_blank_line}
          end
        else
          -- No hay líneas después, está al final del archivo
          associated_element = {type = "end_of_file", line = #content + 1}
        end

        table.insert(structure.javadocs, {
          start_line = javadoc_start,
          end_line = j,
          content = javadoc_content,
          associated = associated_element
        })

        i = j + 1  -- Continuar desde después del cierre del JavaDoc
      else
        -- JavaDoc sin cierre, tratarlo como comentario flotante
        table.insert(structure.floating_comments, {
          start_line = javadoc_start,
          content = javadoc_content,
          type = "unclosed_javadoc"
        })
        i = j  -- Continuar desde donde quedamos
      end

    -- Detectar anotaciones
    elseif line:match("^%s*@[%w_]+") then
      table.insert(structure.annotations, {line = i, content = line})

    -- Detectar declaración de clase
    elseif line:match("^%s*public%s+class%s+") or
           line:match("^%s*class%s+") or
           line:match("^%s*public%s+interface%s+") or
           line:match("^%s*interface%s+") or
           line:match("^%s*public%s+enum%s+") or
           line:match("^%s*enum%s+") then
      structure.class_declaration = {line = i, content = line}

    -- Detectar métodos
    elseif line:match("^%s*public%s+[%w_.<>]+%s+[%w_]+%s*%(") or
           line:match("^%s*private%s+[%w_.<>]+%s+[%w_]+%s*%(") or
           line:match("^%s*protected%s+[%w_.<>]+%s+[%w_]+%s*%(") then
      table.insert(structure.methods, {line = i, content = line})

    -- Detectar comentarios flotantes (no JavaDoc)
    elseif line:match("^%s*//") then
      table.insert(structure.floating_comments, {
        line = i,
        content = line,
        type = "line_comment"
      })
    end

    i = i + 1
  end

  return structure
end

-- Función para validar la estructura de documentación Java
local function validate_java_structure(structure)
  local issues = {}

  -- 1. Verificar JavaDocs flotantes (no asociados a elementos reconocibles)
  for i, javadoc in ipairs(structure.javadocs) do
    if not javadoc.associated or javadoc.associated.type == "unknown" then
      table.insert(issues, {
        type = "floating_javadoc",
        message = "JavaDoc no asociado a ningún elemento reconocible en línea " .. javadoc.start_line,
        line = javadoc.start_line
      })
    end
  end

  -- 2. Verificar JavaDocs antes de imports
  for i, javadoc in ipairs(structure.javadocs) do
    if structure.package and javadoc.start_line > structure.package.line and
       #structure.imports > 0 and javadoc.start_line < structure.imports[1].line then
      table.insert(issues, {
        type = "javadoc_before_imports",
        message = "JavaDoc colocado entre package e imports en línea " .. javadoc.start_line,
        line = javadoc.start_line
      })
    end
  end

  -- 3. Verificar JavaDocs entre imports
  for i, javadoc in ipairs(structure.javadocs) do
    if #structure.imports >= 2 then
      for j = 1, #structure.imports - 1 do
        if javadoc.start_line > structure.imports[j].line and
           javadoc.start_line < structure.imports[j+1].line then
          table.insert(issues, {
            type = "javadoc_between_imports",
            message = "JavaDoc colocado entre imports en línea " .. javadoc.start_line,
            line = javadoc.start_line
          })
        end
      end
    end
  end

  -- 4. Verificar documentación de clase/interfaz
  if structure.class_declaration then
    local class_javadoc_found = false
    local annotation_before_class = false
    local nearest_annotation_line = nil

    -- Verificar si hay anotaciones antes de la clase
    for _, anno in ipairs(structure.annotations) do
      if anno.line < structure.class_declaration.line then
        annotation_before_class = true
        if not nearest_annotation_line or anno.line > nearest_annotation_line then
          nearest_annotation_line = anno.line
        end
      end
    end

    -- Verificar si hay JavaDoc para la clase y su posición
    for _, javadoc in ipairs(structure.javadocs) do
      if javadoc.associated and
         (javadoc.associated.type == "class" or
          (javadoc.associated.type == "annotation" and annotation_before_class)) then
        class_javadoc_found = true

        -- Verificar si está correctamente posicionado
        if annotation_before_class and nearest_annotation_line then
          -- Si hay anotaciones, el JavaDoc debe estar antes de la primera anotación
          if javadoc.start_line >= nearest_annotation_line then
            table.insert(issues, {
              type = "class_javadoc_after_annotation",
              message = "JavaDoc de clase colocado después de anotaciones en línea " .. javadoc.start_line,
              line = javadoc.start_line
            })
          end
        elseif javadoc.start_line >= structure.class_declaration.line then
          -- Si no hay anotaciones, debe estar antes de la declaración de clase
          table.insert(issues, {
            type = "class_javadoc_after_declaration",
            message = "JavaDoc de clase colocado después de la declaración de clase en línea " .. javadoc.start_line,
            line = javadoc.start_line
          })
        end
      end
    end

    if not class_javadoc_found then
      table.insert(issues, {
        type = "missing_class_javadoc",
        message = "Falta JavaDoc para la clase/interfaz",
        line = structure.class_declaration.line
      })
    end
  end

  -- 5. Verificar documentación de métodos
  for _, method in ipairs(structure.methods) do
    local method_javadoc_found = false

    for _, javadoc in ipairs(structure.javadocs) do
      if javadoc.associated and javadoc.associated.type == "method" and
         javadoc.associated.line == method.line then
        method_javadoc_found = true
      end
    end

    if not method_javadoc_found then
      table.insert(issues, {
        type = "missing_method_javadoc",
        message = "Falta JavaDoc para el método en línea " .. method.line,
        line = method.line
      })
    end
  end

  -- 6. Verificar comentarios de implementación flotantes
  for _, comment in ipairs(structure.floating_comments) do
    if comment.type == "line_comment" and comment.content:match("implementation") then
      table.insert(issues, {
        type = "floating_implementation_comment",
        message = "Comentario 'implementation' flotante en línea " .. comment.line,
        line = comment.line
      })
    end
  end

  -- 7. Verificar JavaDocs duplicados para el mismo elemento
  local element_javadoc_count = {}

  for _, javadoc in ipairs(structure.javadocs) do
    if javadoc.associated then
      local key = javadoc.associated.type .. ":" .. tostring(javadoc.associated.line)
      element_javadoc_count[key] = (element_javadoc_count[key] or 0) + 1

      if element_javadoc_count[key] > 1 then
        table.insert(issues, {
          type = "duplicate_javadoc",
          message = "JavaDoc duplicado para el mismo elemento en línea " .. javadoc.start_line,
          line = javadoc.start_line
        })
      end
    end
  end

  return issues
end

-- Función para probar el caso específico proporcionado
local function test_specific_java_case()
  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Establecer tipo de archivo
  vim.bo[1].filetype = "java"

  -- Configurar el buffer con el ejemplo problemático exacto
  mock.buffer_content = {
    "package com.pagerduty.shiftmanagement.flexibleschedules.shared.services;",
    "",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.entities.ScheduleOverrideShiftEntity;",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.models.members.Member;",
    "import com.pagerduty.shiftmanagement.flexibleschedules.shared.models.shifts.OverrideShift;",
    "import java.util.Map;",
    "import java.util.UUID;",
    "import org.springframework.stereotype.Service;",
    "/**",
    " * Service class responsible for mapping {@link ScheduleOverrideShiftEntity} objects to {@link OverrideShift} domain models.",
    " * <p>",
    " * This class provides methods to convert persistence entities into domain objects, resolving member references using a provided map.",
    " */",
    "    /**",
    "     * Maps a {@link ScheduleOverrideShiftEntity} to an {@link OverrideShift} domain object.",
    "     *",
    "     * @param entity  the {@link ScheduleOverrideShiftEntity} to be mapped",
    "     * @param members a map of member UUIDs to {@link Member} objects, used to resolve overridden and overriding members",
    "     * @return the mapped {@link OverrideShift} domain object",
    "     * @throws NullPointerException if {@code entity} or {@code members} is null, or if {@code entity.getOverridingMemberId()} is not present in {@code members}",
    "     */",
    "        // implementation",
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

  -- Analizar la estructura
  print_subheader("Analizando estructura del archivo Java")
  local structure = analyze_java_structure(mock.buffer_content)

  -- Mostrar estadísticas básicas
  print("Package: " .. (structure.package and structure.package.line or "no encontrado"))
  print("Imports: " .. #structure.imports)
  print("JavaDocs: " .. #structure.javadocs)
  print("Anotaciones: " .. #structure.annotations)
  print("Declaración de clase: " .. (structure.class_declaration and structure.class_declaration.line or "no encontrada"))
  print("Métodos: " .. #structure.methods)
  print("Comentarios flotantes: " .. #structure.floating_comments)

  -- Mostrar detalles de JavaDocs
  print("\nDetalles de JavaDocs encontrados:")
  for i, javadoc in ipairs(structure.javadocs) do
    local associated_type = javadoc.associated and javadoc.associated.type or "ninguno"
    local associated_line = javadoc.associated and javadoc.associated.line or "N/A"
    print("  JavaDoc #" .. i .. " (líneas " .. javadoc.start_line .. "-" .. javadoc.end_line ..
          "): asociado a " .. associated_type .. " en línea " .. associated_line)
  end

  -- Validar la estructura
  print_subheader("Validando estructura de documentación")
  local issues = validate_java_structure(structure)

  -- Mostrar resultados
  if #issues == 0 then
    print("✅ No se encontraron problemas de formato en la documentación Java")
  else
    print("❌ Se encontraron " .. #issues .. " problemas de formato en la documentación:")
    for i, issue in ipairs(issues) do
      print("  " .. i .. ". [" .. issue.type .. "] " .. issue.message)
    end
  end

  return #issues == 0, issues
end

-- Función para probar una estructura correcta
local function test_correct_java_structure()
  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Establecer tipo de archivo
  vim.bo[1].filetype = "java"

  -- Configurar el buffer con una estructura correcta
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
    "/**",
    " * Service class responsible for mapping {@link ScheduleOverrideShiftEntity} objects to {@link OverrideShift} domain models.",
    " * <p>",
    " * This class provides methods to convert persistence entities into domain objects, resolving member references using a provided map.",
    " */",
    "@Service",
    "public class OverrideShiftMapper {",
    "",
    "  /**",
    "   * Maps a {@link ScheduleOverrideShiftEntity} to an {@link OverrideShift} domain object.",
    "   *",
    "   * @param entity  the {@link ScheduleOverrideShiftEntity} to be mapped",
    "   * @param members a map of member UUIDs to {@link Member} objects, used to resolve overridden and overriding members",
    "   * @return the mapped {@link OverrideShift} domain object",
    "   * @throws NullPointerException if {@code entity} or {@code members} is null, or if {@code entity.getOverridingMemberId()} is not present in {@code members}",
    "   */",
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

  -- Analizar la estructura
  print_subheader("Analizando estructura correcta del archivo Java")
  local structure = analyze_java_structure(mock.buffer_content)

  -- Validar la estructura
  print_subheader("Validando estructura de documentación correcta")
  local issues = validate_java_structure(structure)

  -- Mostrar resultados
  if #issues == 0 then
    print("✅ No se encontraron problemas de formato en la documentación Java (como se esperaba)")
  else
    print("❌ Se encontraron " .. #issues .. " problemas de formato en la estructura correcta (inesperado):")
    for i, issue in ipairs(issues) do
      print("  " .. i .. ". [" .. issue.type .. "] " .. issue.message)
    end
  end

  return #issues == 0, issues
end

-- Ejecutar pruebas
print_header("VALIDACIÓN DE ESTRUCTURA DE DOCUMENTACIÓN JAVA")

print_header("1. PRUEBA CON CASO ESPECÍFICO PROBLEMÁTICO")
local specific_ok, specific_issues = test_specific_java_case()

print_header("2. PRUEBA CON ESTRUCTURA CORRECTA")
local correct_ok, correct_issues = test_correct_java_structure()

print_header("RESULTADOS FINALES")

if specific_ok and correct_ok then
  print("✅ Las validaciones de estructura pasaron correctamente (inesperado para el caso problemático)")
  print("⚠️  Es posible que la validación no esté detectando todos los problemas correctamente")
  os.exit(1)
elseif not specific_ok and correct_ok then
  print("✅ La validación detectó correctamente los problemas en el caso específico")
  print("✅ La validación pasó correctamente el caso con estructura correcta")

  print("\nSe encontraron los siguientes problemas en el caso específico:")
  for i, issue in ipairs(specific_issues) do
    print("  " .. i .. ". " .. issue.message)
  end

  print("\n✅ La validación funciona correctamente")
  os.exit(0)
else
  print("❌ La validación no funciona correctamente")
  print("  - Caso problemático detectado correctamente: " .. (not specific_ok and "Sí" or "No"))
  print("  - Caso correcto validado correctamente: " .. (correct_ok and "Sí" or "No"))
  os.exit(1)
end