-- Módulo para gestionar aplicación de patches a archivos
-- Migrado y adaptado desde CopilotFiles

local M = {}
local log = require("copilotchatassist.utils.log")

-- Extrae patches de un texto y los devuelve como lista
-- @param text string: Texto de donde extraer los patches
-- @return table: Lista de patches encontrados
function M.get_patches_from_text(text)
  local parser = require("copilotchatassist.patches.parser")
  local lines = vim.split(text, "\n")
  return parser.parse_patches(lines)
end

-- Muestra una vista previa del patch y pide confirmación antes de aplicarlo
-- @param patch table: El patch a mostrar
-- @param apply_callback function: Función a llamar si se confirma
-- @param callback function: Función a llamar después (opcional)
local function show_patch_preview_and_confirm(patch, apply_callback, callback)
  -- Preparar líneas para la vista previa
  local preview_lines = {}
  table.insert(preview_lines, string.format("Archivo: %s", patch.archivo or "?"))
  table.insert(preview_lines, string.format("Modo: %s", patch.modo or "?"))
  table.insert(preview_lines, string.format("Líneas: %s-%s",
    tostring(patch.start_line) or "?",
    tostring(patch.end_line) or "?"))
  table.insert(preview_lines, "")

  -- Añadir contenido del patch
  for line in (patch.block or ""):gmatch("[^\r\n]+") do
    table.insert(preview_lines, line)
  end

  -- Crear buffer y ventana flotante
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines)

  -- Calcular dimensiones óptimas
  local width = math.max(40, math.min(80, vim.o.columns - 10))
  local height = math.max(10, math.min(20, vim.o.lines - 6))

  -- Crear ventana flotante
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
  })

  -- Solicitar confirmación
  local confirm = vim.fn.confirm("¿Aplicar patch al archivo?", "&Sí\n&No", 1)
  vim.api.nvim_win_close(win, true)

  if confirm == 1 then
    log.debug(string.format("Patch confirmado para aplicar: archivo=%s, start_line=%s, end_line=%s, modo=%s",
      tostring(patch.archivo), tostring(patch.start_line), tostring(patch.end_line), tostring(patch.modo)))
    apply_callback()
  else
    log.debug("Usuario canceló la aplicación del patch en la vista previa")
    if callback then callback() end
  end
end

-- Aplica todos los patches en la cola
-- @param patch_queue table: Cola de patches a aplicar
function M.apply_patch_queue(patch_queue)
  log.debug("Iniciando aplicación de patches en cola")

  -- Verificar que la cola tenga items
  if not patch_queue or not patch_queue.items or #patch_queue.items == 0 then
    log.info("No hay patches en la cola para aplicar")
    return
  end

  -- Aplicar cada patch en la cola
  for i, patch in ipairs(patch_queue.items) do
    if patch.estado == "pendiente" then
      log.debug("Aplicando patch " .. i .. " de " .. #patch_queue.items)

      -- Crear función de callback que actualice el estado
      local function update_status(success)
        if success then
          patch_queue:update_status(i, "aplicado")
        else
          patch_queue:update_status(i, "fallido")
        end
      end

      -- Aplicar el patch
      local success = M.apply_patch(patch, function() update_status(true) end)
      if not success then
        update_status(false)
      end
    end
  end
end

-- Aplica un patch a un archivo, mostrando vista previa y confirmación
-- @param patch table: El patch a aplicar
-- @param callback function: Función a llamar después (opcional)
-- @return boolean: true si se aplicó o se intentó aplicar, false si se rechazó por validación
function M.apply_patch(patch, callback)
  log.debug("Patch recibido para aplicación:\n" .. vim.inspect(patch))

  -- Extraer metadatos del patch
  local path = patch.archivo
  local mode = patch.modo
  local start_line = patch.start_line
  local end_line = patch.end_line

  log.debug("Archivo destino: " .. tostring(path))
  log.debug("Modo: " .. tostring(mode))
  log.debug("Línea inicio: " .. tostring(start_line))
  log.debug("Línea fin: " .. tostring(end_line))
  log.debug("Contenido:\n" .. (patch.block or "<nil>"))

  -- Validación de metadatos requeridos
  if not path or not mode then
    log.warn("Patch sin metadatos requeridos (archivo, modo), ignorando")
    if callback then callback() end
    return false
  end

  -- Filtrar paths inválidos (debe ser absoluto y tener extensión)
  if not path:match("^/") or not path:match("%.%w+$") then
    log.warn("Path inválido (no es un archivo), ignorando patch: " .. tostring(path))
    if callback then callback() end
    return false
  end

  -- Crear directorio si no existe
  local dir = path:match("(.+)/[^/]+$")
  if dir and vim.fn.isdirectory(dir) == 0 then
    log.debug("Creando directorio: " .. dir)
    local ok = vim.fn.mkdir(dir, "p")
    if ok == 0 then
      log.error("Error al crear directorio: " .. dir)
      if callback then callback() end
      return false
    end
  end

  -- Crear archivo vacío si no existe
  if vim.fn.filereadable(path) == 0 then
    log.debug("Creando archivo vacío: " .. path)
    local f, err = io.open(path, "w")
    if not f then
      log.error("Error al crear archivo: " .. tostring(err))
      if callback then callback() end
      return false
    else
      f:close()
    end
  end

  -- Cargar buffer y obtener número de líneas
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  local last_line = vim.api.nvim_buf_line_count(bufnr)

  -- Convertir marcadores de línea a números reales
  if start_line == "<última línea>" or start_line == "<last line>" then
    log.debug("Convirtiendo marcador de start_line a: " .. tostring(last_line))
    start_line = last_line
  end
  if end_line == "<última línea>" or end_line == "<last line>" then
    log.debug("Convirtiendo marcador de end_line a: " .. tostring(last_line))
    end_line = last_line
  end

  log.debug(string.format("Preparando aplicación de patch: path=%s, start_line=%s, end_line=%s, mode=%s",
    path, start_line or "?", end_line or "?", mode))

  -- Verificar contenido para modos que lo requieren
  local content = patch.block
  if (not content or content == "") and mode ~= "delete" then
    log.warn("Patch sin contenido, ignorando")
    if callback then callback() end
    return false
  end

  -- Función para aplicar el patch al buffer
  local function do_apply()
    log.debug("Aplicando patch al buffer: " .. path)
    log.debug("Número de buffer destino: " .. tostring(bufnr))

    -- Validar antes de aplicar
    if not start_line or not end_line then
      log.error("El patch no tiene línea de inicio o fin")
      log.error("Patch sin línea de inicio o fin, no se puede aplicar")
      if callback then callback() end
      return
    end

    -- Convertir a números
    start_line = tonumber(start_line)
    end_line = tonumber(end_line)

    -- Convertir contenido a líneas
    local lines = vim.split(content or "", "\n")
    local last_line_buf = vim.api.nvim_buf_line_count(bufnr)

    -- Debug de líneas
    log.debug("Líneas de patch a aplicar:")
    for i, line in ipairs(lines) do
      log.debug(string.format("  [%d] %s", i, line))
    end

    -- Aplicar según el modo
    if mode == "replace" and start_line == 1 and end_line == last_line_buf then
      log.debug("Reemplazando contenido completo del archivo")
      vim.api.nvim_buf_set_lines(bufnr, 0, last_line_buf, false, lines)
    elseif mode == "replace" then
      log.debug(string.format("Reemplazando líneas %d a %d", start_line, end_line))
      vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, lines)
    elseif mode == "insert" then
      log.debug(string.format("Insertando en línea %d", start_line))
      vim.api.nvim_buf_set_lines(bufnr, start_line - 1, start_line - 1, false, lines)
    elseif mode == "append" then
      log.debug(string.format("Añadiendo después de línea %d", end_line))
      vim.api.nvim_buf_set_lines(bufnr, end_line, end_line, false, lines)
    elseif mode == "delete" then
      log.debug(string.format("Eliminando líneas %d a %d", start_line, end_line))
      vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, {})
    end

    -- Guardar buffer después de aplicar el patch
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("write") end)
    log.debug("Buffer guardado: " .. path)

    if callback then callback() end
  end

  -- Mostrar vista previa y pedir confirmación antes de aplicar
  show_patch_preview_and_confirm(patch, do_apply, callback)
  return true
end

return M