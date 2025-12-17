-- Módulo para análisis de Git diff y seguimiento de comentarios
-- Detecta cambios en archivos y actualiza el estado de los comentarios

local M = {}
local log = require("copilotchatassist.utils.log")
local i18n = require("copilotchatassist.i18n")

-- Parsear un diff de Git
function M.parse_git_diff(diff_content)
  if not diff_content or diff_content == "" then
    return {}
  end

  local diff_files = {}
  local current_file = nil
  local hunks = {}

  -- Dividir por líneas
  local lines = {}
  for line in diff_content:gmatch("([^\n]*)\n?") do
    table.insert(lines, line)
  end

  -- Procesar líneas
  for i, line in ipairs(lines) do
    -- Nueva cabecera de archivo
    if line:match("^diff %-%-git") then
      -- Guardar archivo anterior si existe
      if current_file then
        diff_files[current_file.file] = current_file
      end

      -- Iniciar nuevo archivo
      current_file = {
        file = nil,
        hunks = {},
        lines_added = 0,
        lines_removed = 0,
        binary = false
      }

      -- Extraer nombre del archivo (a/ y b/ son prefijos de git)
      local match_b = lines[i+2] and lines[i+2]:match("^%+%+%+ b/(.+)")
      if match_b then
        current_file.file = match_b
      end
    end

    -- Detectar archivos binarios
    if line:match("^Binary files") then
      if current_file then
        current_file.binary = true
      end
    end

    -- Nueva sección de cambios (hunk)
    if line:match("^@@") then
      -- Extraer información del hunk
      local old_start, old_count, new_start, new_count =
        line:match("^@@%s%-(%d+),?(%d*)%s%+(%d+),?(%d*)%s@@")

      old_start = tonumber(old_start) or 1
      old_count = tonumber(old_count) or 1
      new_start = tonumber(new_start) or 1
      new_count = tonumber(new_count) or 1

      local hunk = {
        old_start = old_start,
        old_count = old_count,
        new_start = new_start,
        new_count = new_count,
        content = {},
        context_before = {},
        context_after = {}
      }

      -- Guardar contexto antes del hunk si está disponible
      local context_start = math.max(1, i - 3)
      for j = context_start, i - 1 do
        if lines[j] and not lines[j]:match("^diff") and not lines[j]:match("^@@") and
           not lines[j]:match("^%-%-%- ") and not lines[j]:match("^%+%+%+ ") then
          table.insert(hunk.context_before, lines[j])
        end
      end

      -- Añadir hunk a lista
      if current_file then
        table.insert(current_file.hunks, hunk)
      end
    end

    -- Líneas de contenido de hunk
    if line:match("^%+") or line:match("^%-") or line:match("^ ") then
      if current_file and #current_file.hunks > 0 then
        local hunk = current_file.hunks[#current_file.hunks]
        table.insert(hunk.content, line)

        -- Contar líneas añadidas/eliminadas
        if line:match("^%+") and not line:match("^%+%+%+ ") then
          current_file.lines_added = current_file.lines_added + 1
        elseif line:match("^%-") and not line:match("^%-%-%- ") then
          current_file.lines_removed = current_file.lines_removed + 1
        end
      end
    end
  end

  -- No olvidar el último archivo
  if current_file and current_file.file then
    diff_files[current_file.file] = current_file
  end

  return diff_files
end

-- Generar un hash para un fragmento de código
function M.hash_code_snippet(code)
  if not code or code == "" then
    return ""
  end

  -- Eliminar espacios en blanco y normalizar
  local normalized = code:gsub("%s+", " ")

  -- Método simple de hash para propósitos de comparación
  local hash = 0
  for i = 1, #normalized do
    local char = string.byte(normalized, i)
    hash = ((hash * 31) + char) % 2147483647
  end

  return tostring(hash)
end

-- Comprobar si un comentario sigue siendo válido después de cambios
function M.is_comment_still_valid(comment, diff_files)
  if not comment or not comment.file then
    return false
  end

  -- Si el archivo no ha cambiado, el comentario sigue siendo válido
  if not diff_files[comment.file] then
    return true
  end

  -- Obtener los cambios del archivo
  local file_diff = diff_files[comment.file]

  -- Comprobar si la línea del comentario ha sido eliminada/modificada
  local comment_line = comment.line
  local deleted = false

  for _, hunk in ipairs(file_diff.hunks) do
    -- Calcular rango de líneas afectadas en el archivo original
    local old_start = hunk.old_start
    local old_end = old_start + hunk.old_count - 1

    -- Verificar si la línea del comentario está en el rango afectado
    if comment_line >= old_start and comment_line <= old_end then
      -- Buscar en el contenido del hunk para ver si la línea específica fue eliminada/modificada
      local line_offset = comment_line - old_start
      for i, line in ipairs(hunk.content) do
        if i - 1 == line_offset and line:match("^%-") then
          -- La línea fue eliminada o modificada
          deleted = true
          break
        end
      end
    end
  end

  return not deleted
end

-- Verificar si un comentario ha sido resuelto por los cambios
function M.is_comment_resolved(comment, diff_files)
  if not comment or not comment.file or comment.status == "Solucionado" then
    return false
  end

  -- Si el archivo no ha cambiado, el comentario no ha sido resuelto
  if not diff_files[comment.file] then
    return false
  end

  -- Obtener los cambios del archivo
  local file_diff = diff_files[comment.file]

  -- Comprobar si la línea del comentario ha sido modificada
  local comment_line = comment.line
  local modified = false

  for _, hunk in ipairs(file_diff.hunks) do
    -- Calcular rango de líneas afectadas en el archivo original
    local old_start = hunk.old_start
    local old_end = old_start + hunk.old_count - 1

    -- Verificar si la línea del comentario está en el rango afectado
    if comment_line >= old_start and comment_line <= old_end then
      -- Buscar cambios en esta línea
      local line_offset = comment_line - old_start
      for i, line in ipairs(hunk.content) do
        if i - 1 == line_offset and line:match("^%+") then
          -- La línea fue modificada
          modified = true
          break
        end
      end
    end
  end

  -- Si la línea fue modificada y el hash del código ha cambiado, considerar resuelto
  if modified and comment.code_context and comment.hash then
    -- Obtener contenido actual del archivo
    local file_content = vim.fn.system("cat " .. vim.fn.shellescape(comment.file))
    local lines = {}
    for line in file_content:gmatch("[^\n]+") do
      table.insert(lines, line)
    end

    -- Obtener contexto actual
    local start_idx = math.max(1, comment_line - 2)
    local end_idx = math.min(#lines, comment_line + 2)
    local current_context = table.concat({unpack(lines, start_idx, end_idx)}, "\n")

    -- Generar hash del contexto actual
    local current_hash = M.hash_code_snippet(current_context)

    -- Si el hash cambió, el código ha sido modificado
    return current_hash ~= comment.hash
  end

  return false
end

-- Analizar cambios en los comentarios basados en un nuevo diff
function M.analyze_diff_changes(diff_content, comments)
  if not comments or #comments == 0 then
    return comments
  end

  local diff_files = M.parse_git_diff(diff_content)
  local updated_comments = vim.deepcopy(comments)

  -- Para cada comentario, verificar si sigue siendo válido
  for i, comment in ipairs(updated_comments) do
    -- Si el comentario ya está resuelto, no hacer nada
    if comment.status == "Solucionado" then
      goto continue
    end

    -- Verificar si el comentario sigue siendo válido
    if not M.is_comment_still_valid(comment, diff_files) then
      -- La línea fue eliminada, marcar como resuelto
      updated_comments[i].status = "Solucionado"
      updated_comments[i].updated_at = os.time()
      log.debug(i18n.t("code_review.comment_auto_resolved", {comment.id, comment.file, comment.line}))
    elseif M.is_comment_resolved(comment, diff_files) then
      -- La línea fue modificada de manera que resuelve el comentario
      updated_comments[i].status = "Modificado"
      updated_comments[i].updated_at = os.time()
      log.debug(i18n.t("code_review.comment_modified", {comment.id, comment.file, comment.line}))
    end

    ::continue::
  end

  return updated_comments
end

-- Comprobar si un archivo modificado tiene comentarios
function M.file_has_comments(file_path, comments)
  for _, comment in ipairs(comments or {}) do
    if comment.file == file_path then
      return true
    end
  end
  return false
end

-- Obtener comentarios para un archivo específico
function M.get_file_comments(file_path, comments)
  local file_comments = {}
  for _, comment in ipairs(comments or {}) do
    if comment.file == file_path then
      table.insert(file_comments, comment)
    end
  end
  return file_comments
end

-- Añadir hash a comentarios para seguimiento de cambios
function M.add_hashes_to_comments(comments)
  local updated_comments = vim.deepcopy(comments)

  for i, comment in ipairs(updated_comments) do
    if comment.code_context and comment.code_context ~= "" then
      updated_comments[i].hash = M.hash_code_snippet(comment.code_context)
    end
  end

  return updated_comments
end

return M