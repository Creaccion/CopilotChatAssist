local utils = require("copilotchatassist.utils")
local file_utils = require("copilotchatassist.utils.file")
local log = require("copilotchatassist.utils.log")
local options = require("copilotchatassist.options")
local copilot_api = require("copilotchatassist.copilotchat_api")
local context_prompts = require("copilotchatassist.prompts.context")

local M = {}

function M.get_ticket_id()
  local branch = utils.get_current_branch()
  local project = utils.get_project_name()
  local ticket = branch:match("^([A-Z]+%-%d+)")
  if ticket then
    return project .. "_jira-" .. ticket
  else
    local hash = utils.hash_string(branch)
    return project .. "-" .. hash
  end
end

-- Obtener el ticket de la rama actual
function M.get_ticket_from_branch()
  local branch = utils.get_current_branch()
  return branch:match("^([A-Z]+%-%d+)")
end

-- Obtener la rama actual
function M.get_current_branch()
  return utils.get_current_branch()
end

-- Verificar si un archivo existe en cualquiera de las ubicaciones dadas
function M.find_file_in_possible_locations(file_path, locations)
  for _, location in ipairs(locations) do
    local full_path = location .. "/" .. file_path
    if vim.fn.filereadable(full_path) == 1 then
      return full_path
    end
  end
  return nil
end

function M.get_context_paths()
  local context_dir = options.get().context_dir
  file_utils.ensure_dir(context_dir)
  local project = utils.get_project_name()
  local id = M.get_ticket_id()
  return {
    requirement     = context_dir .. "/" .. id .. "_requirement.md",
    synthesis       = context_dir .. "/" .. id .. "_synthesis.md",
    project_context = context_dir .. "/" .. project .. "_project_synthesis.md",
    todo_path = context_dir .. "/" .. id .. "_todo.md"
  }
end

function M.input_requirement()
  local paths = M.get_context_paths()
  vim.cmd("vsplit " .. paths.requirement)
  vim.notify("Paste or write the requirement, then save and close the buffer.", vim.log.levels.INFO)
end

function M.save_synthesis(content)
  local paths = M.get_context_paths()
  file_utils.write_file(paths.synthesis, content)
  vim.notify("Context synthesis saved: " .. paths.synthesis, vim.log.levels.INFO)
end

function M.save_project_context(content)
  local paths = M.get_context_paths()
  file_utils.write_file(paths.project_context, content)
  vim.notify("Project context saved: " .. paths.project_context, vim.log.levels.INFO)
end

function M.load_requirement()
  local paths = M.get_context_paths()
  return file_utils.read_file(paths.requirement)
end

function M.load_synthesis()
  local paths = M.get_context_paths()
  return file_utils.read_file(paths.synthesis)
end

function M.load_project_context()
  local paths = M.get_context_paths()
  return file_utils.read_file(paths.project_context)
end

function M.analyze_project(requirement)
  vim.notify("Analyzing project with requirement:\n" .. requirement, vim.log.levels.INFO)
end

-- Asynchronous context update for ticket/project
function M.update_context_with_progress(requirement, context_path, callback)
  local current_context = file_utils.read_file(context_path) or ""
  local prompt = [[
Revisa el siguiente contexto y actualízalo incorporando los avances recientes, el camino tomado, archivos modificados, comandos ejecutados y decisiones importantes. Si hay tareas completadas, actualiza la lista. Mantén el contexto claro y útil para futuras consultas.

<requirement>
]] .. requirement .. [[

<contexto_actual>
]] .. current_context .. [[

Incluye:
- Resumen de avances y decisiones tomadas
- Archivos modificados y comandos relevantes
- Actualización de tareas y problemas resueltos
- Sugerencias para próximos pasos

Responde exclusivamente en español a menos que el usuario pida explícitamente otro idioma.
]]

  copilot_api.ask(prompt, {
    headless = true,
    callback = function(response)
      file_utils.write_file(context_path, response or "")
      -- No mostrar ningún mensaje de contexto actualizado
      if callback then callback() end
    end
  })
end

-- Función para continuar con el flujo normal de contextos después del enriquecimiento
function M.continue_with_enriched_context(requirement, paths)
  local ticket_synthesis = file_utils.read_file(paths.synthesis) or ""
  local project_synthesis = file_utils.read_file(paths.project_context) or ""

  M.continue_with_normal_context(requirement, ticket_synthesis, project_synthesis, paths)
end

-- Función para continuar con el flujo normal de contextos
function M.continue_with_normal_context(requirement, ticket_synthesis, project_synthesis, paths)
  -- Si no hay síntesis de ticket, generarla
  if not (ticket_synthesis and #ticket_synthesis > 10) then
    vim.notify("Generating ticket synthesis...", vim.log.levels.INFO)
    M.analyze_ticket_context(requirement)
    ticket_synthesis = file_utils.read_file(paths.synthesis)
  end

  -- Si falta síntesis de proyecto, generarla y espera a que esté lista antes de continuar
  if not (project_synthesis and #project_synthesis > 10) then
    vim.notify("Generating project synthesis...", vim.log.levels.INFO)
    M.analyze_project_context(requirement)
    vim.defer_fn(function()
      local updated_project_synthesis = file_utils.read_file(paths.project_context)
      if updated_project_synthesis and #updated_project_synthesis > 10 then
        M.copilot_tickets()
      else
        vim.notify("Project synthesis not ready yet. Please try again in a moment.", vim.log.levels.WARN)
      end
    end, 1500)
    return
  end

  -- Actualizar contextos existentes antes de combinar
  M.update_context_with_progress(requirement, paths.synthesis, function()
    M.update_context_with_progress(requirement, paths.project_context, function()
      local combine_contexts = function()
        local updated_ticket_synthesis = file_utils.read_file(paths.synthesis)
        local updated_project_synthesis = file_utils.read_file(paths.project_context)
        local context_parts = {}
        if requirement and #requirement > 10 then
          table.insert(context_parts, "-- Requirement Context --\n" .. requirement)
        end
        if updated_ticket_synthesis and #updated_ticket_synthesis > 10 then
          table.insert(context_parts, "-- Ticket Synthesis --\n" .. updated_ticket_synthesis)
        end
        if updated_project_synthesis and #updated_project_synthesis > 10 then
          table.insert(context_parts, "-- Project Synthesis --\n" .. updated_project_synthesis)
        end

        if #context_parts > 0 then
          local full_context = table.concat(context_parts, "\n\n")
          local i18n = require("copilotchatassist.i18n")
          local notify = require("copilotchatassist.utils.notify")

          -- Usar el manejador de contexto para guardar y aplicar el contexto
          local context_handler = require("copilotchatassist.utils.context_handler")
          context_handler.store_context(full_context)

          -- Intentar aplicar inmediatamente si CopilotChat está disponible
          if context_handler.apply_context_to_chat() then
            notify.info(i18n.t("context.context_loaded_combined"))
          else
            -- Fallback al método anterior si CopilotChat no está disponible
            notify.info(i18n.t("context.context_loaded_combined"))
            copilot_api.ask(full_context)
          end
          return
        end

        local i18n = require("copilotchatassist.i18n")
        local notify = require("copilotchatassist.utils.notify")
        notify.warn(i18n.t("context.no_context_files"), {force = true})
      end

      combine_contexts()
    end)
  end)
end

function M.copilot_tickets()
  local paths = M.get_context_paths()
  local requirement = file_utils.read_file(paths.requirement)
  local ticket_synthesis = file_utils.read_file(paths.synthesis)
  local project_synthesis = file_utils.read_file(paths.project_context)

  -- Si no hay ningún archivo de contexto, requerimiento o proyecto, preguntar antes de generar
  local no_context_files = not (requirement and #requirement > 10)
    and not (ticket_synthesis and #ticket_synthesis > 10)
    and not (project_synthesis and #project_synthesis > 10)

  if no_context_files then
    vim.ui.select({ "Sí", "No" }, {
      prompt = "¿Desea crear el contexto y los archivos requeridos para este ticket/proyecto?",
    }, function(choice)
      if choice == "Sí" then
        -- Continuar con el flujo normal
        if not (requirement and #requirement > 10) then
          local branch = utils.get_current_branch()
          local ticket = branch:match("^([A-Z]+%-%d+)")
          if ticket then
            local jira_url = "https://pagerduty.atlassian.net/browse/" .. ticket
            vim.fn.jobstart({ "open", jira_url }, { detach = true })
            vim.notify("Jira ticket detected: " .. ticket .. ". Paste the requirement from Jira in the buffer.",
              vim.log.levels.INFO)
          else
            -- Fallback al método anterior si CopilotChat no está disponible
            notify.info(i18n.t("context.context_loaded_combined"))
            copilot_api.ask(full_context)
          end
          return
        end

        local i18n = require("copilotchatassist.i18n")
        local notify = require("copilotchatassist.utils.notify")
        notify.warn(i18n.t("context.no_context_files"), {force = true})
      end

      combine_contexts()
    end)
  end)
end

-- Intenta extraer la ruta de un archivo solicitado del mensaje actual de Copilot
function M.try_autodetect_requested_file()
  local log = require("copilotchatassist.utils.log")
  log.info("Intentando detectar archivo solicitado automáticamente")

  -- Verificar si hay un archivo activo (visible) en algún buffer
  local current_file = vim.fn.expand("%:p")
  if current_file and current_file ~= "" then
    log.debug("Archivo actual: " .. current_file)
    return current_file
  end

  -- Buscar en el buffer de entrada (visible) de CopilotChat para extraer rutas de archivo
  local function extract_file_from_input_buffer()
    -- Intenta identificar el buffer de entrada de CopilotChat
    local found_buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name:match("CopilotChat") or buf_name:match("copilot%-chat") then
        table.insert(found_buffers, buf)
      end
    end

    -- Examinar el contenido del buffer de entrada
    for _, buf in ipairs(found_buffers) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local content = table.concat(lines, "\n")

        -- Buscar patrones como rutas de archivo (absolutas o relativas)
        -- Primero buscar rutas absolutas
        local absolute_path = content:match("/[%w%._%-/]+%.%w+")
        if absolute_path then
          log.info("Ruta absoluta detectada: " .. absolute_path)
          return absolute_path
        end

        -- Buscar rutas a archivos Java comunes si no hay ruta absoluta
        -- Patrones para archivos Java (por ejemplo: com.company.package.ClassName)
        local java_class = content:match("([%w%.]+%.%w+Repository)")
        if java_class then
          -- Convertir notación de punto a ruta de archivo
          local file_path = java_class:gsub("%.", "/") .. ".java"
          log.info("Clase Java detectada: " .. java_class .. " -> " .. file_path)

          -- Intenta encontrar el archivo en el proyecto
          local root = vim.fn.getcwd()
          local possible_paths = {
            root .. "/src/main/java/" .. file_path,
            root .. "/apps/flexible-schedules/shared/src/main/java/" .. file_path,
            root .. "/apps/flexible-schedules/api/src/main/java/" .. file_path,
            root .. "/apps/flexible-schedules/domain/src/main/java/" .. file_path
          }

          -- Verifica cada ruta posible
          for _, path in ipairs(possible_paths) do
            if vim.fn.filereadable(path) == 1 then
              log.info("Archivo Java encontrado en: " .. path)
              return path
            end
          end

          -- Si no se encuentra, devolver la primera ruta posible
          log.warn("No se encontró el archivo Java exacto, usando primera ruta posible")
          return possible_paths[1]
        end
      end
    end

    return nil
  end

  return extract_file_from_input_buffer()
end

-- Detecta el tipo de archivo basado en la extensión
function M.detect_file_type(file_path)
  if not file_path then return "" end

  local ext = file_path:match("%.([-_%w]+)$")
  if not ext then return "" end

  ext = ext:lower()

  local file_types = {
    java = "java",
    py = "python",
    js = "javascript",
    ts = "typescript",
    jsx = "jsx",
    tsx = "tsx",
    php = "php",
    rb = "ruby",
    lua = "lua",
    go = "go",
    rs = "rust",
    c = "c",
    cpp = "cpp",
    h = "c",
    hpp = "cpp",
    json = "json",
    xml = "xml",
    yaml = "yaml",
    yml = "yaml",
    md = "markdown"
  }

  return file_types[ext] or ""
end

-- Lee el contenido de un archivo
function M.read_file_content(file_path)
  if not file_path or file_path == "" then return nil end

  local file = io.open(file_path, "r")
  if not file then return nil end

  local content = file:read("*a")
  file:close()

  return content
end

-- Función para detectar y agregar manualmente un archivo solicitado
function M.detect_and_add_requested_file()
  local notify = require("copilotchatassist.utils.notify")

  local detected_file = M.try_autodetect_requested_file()

  if detected_file then
    -- Obtener rutas de archivos de contexto
    local paths = M.get_context_paths()

    -- Leer el contenido del archivo de requerimientos existente
    local requirement = file_utils.read_file(paths.requirement) or ""

    -- Verificar si el archivo ya está incluido
    if requirement:find(detected_file:gsub("%W", "%%%1")) then
      notify.info("El archivo ya está incluido en el contexto: " .. detected_file)
      return
    end

    -- Agregar el contenido del archivo detectado
    local file = io.open(paths.requirement, "a")
    if file then
      file:write("\n\n## Archivo detectado manualmente: " .. detected_file .. "\n\n")
      file:write("```" .. M.detect_file_type(detected_file) .. "\n")
      local file_content = M.read_file_content(detected_file)
      if file_content then
        file:write(file_content)
      else
        file:write("// Error al leer el archivo solicitado: " .. detected_file)
      end
      file:write("\n```\n")
      file:close()

      -- Notificar al usuario
      notify.success("Archivo agregado al contexto: " .. detected_file)

      -- Abrir el archivo de requerimientos para mostrar el cambio
      vim.cmd("edit " .. paths.requirement)
    else
      notify.error("Error al actualizar el archivo de requerimientos")
    end
  else
    -- Si no se detectó automáticamente, preguntar al usuario
    vim.ui.input({
      prompt = "Ingrese la ruta del archivo a agregar: ",
    }, function(input)
      if input and input ~= "" then
        -- Usar el archivo proporcionado por el usuario
        local file_path = input

        -- Verificar si el archivo existe
        if vim.fn.filereadable(file_path) ~= 1 then
          notify.error("El archivo no existe: " .. file_path)
          return
        end

        -- Obtener rutas de archivos de contexto
        local paths = M.get_context_paths()

        -- Leer el contenido del archivo de requerimientos existente
        local requirement = file_utils.read_file(paths.requirement) or ""

        -- Verificar si el archivo ya está incluido
        if requirement:find(file_path:gsub("%W", "%%%1")) then
          notify.info("El archivo ya está incluido en el contexto: " .. file_path)
          return
        end

        -- Agregar el contenido del archivo detectado
        local file = io.open(paths.requirement, "a")
        if file then
          file:write("\n\n## Archivo agregado manualmente: " .. file_path .. "\n\n")
          file:write("```" .. M.detect_file_type(file_path) .. "\n")
          local file_content = M.read_file_content(file_path)
          if file_content then
            file:write(file_content)
          else
            file:write("// Error al leer el archivo: " .. file_path)
          end
          file:write("\n```\n")
          file:close()

          -- Notificar al usuario
          notify.success("Archivo agregado al contexto: " .. file_path)

          -- Abrir el archivo de requerimientos para mostrar el cambio
          vim.cmd("edit " .. paths.requirement)
        else
          notify.error("Error al actualizar el archivo de requerimientos")
        end
      end
    end)
  end
end

function M.copilot_tickets()
  -- Esta función prepara y muestra la ventana para trabajar con tickets
  -- y contexto de Copilot

  local notify = require("copilotchatassist.utils.notify")
  notify.info("Preparando contexto para ticket...")

  local ticket = M.get_ticket_from_branch()
  if not ticket then
    notify.warn("No se pudo determinar ticket desde la rama")
  end

  -- Crear directorio de tickets si no existe
  local ticket_dir = M.get_ticket_dir()
  if vim.fn.isdirectory(ticket_dir) == 0 then
    vim.fn.mkdir(ticket_dir, "p")
  end

  -- Obtener rutas de archivos de contexto
  local paths = M.get_context_paths()

  -- Intentar autodetectar y cargar el archivo mencionado en la solicitud actual
  local auto_detected_file = M.try_autodetect_requested_file()

  -- Si no existe archivo de requerimientos, crearlo con contenido inicial
  if vim.fn.filereadable(paths.requirement) == 0 then
    local content = "# Requerimiento del ticket " .. (ticket or "Actual") .. "\n\n"
    content = content .. "Describe aquí el requerimiento o tarea a realizar.\n\n"
    content = content .. "## Información adicional\n\n"

    if ticket then
      content = content .. "- Ticket: " .. ticket .. "\n"
    end

    content = content .. "- Branch: " .. utils.get_current_branch() .. "\n"

    -- Si se detectó un archivo automáticamente, agregarlo al contenido
    if auto_detected_file then
      content = content .. "\n## Archivo solicitado\n\n"
      content = content .. "```" .. M.detect_file_type(auto_detected_file) .. "\n"
      local file_content = M.read_file_content(auto_detected_file)
      if file_content then
        content = content .. file_content
      else
        content = content .. "// Error al leer el archivo solicitado: " .. auto_detected_file
      end
      content = content .. "\n```\n"
    end

    -- Guardar el contenido inicial
    local file = io.open(paths.requirement, "w")
    if file then
      file:write(content)
      file:close()
    end
  elseif auto_detected_file then
    -- Si el archivo de requerimientos ya existe y detectamos un archivo automáticamente,
    -- agregar el contenido del archivo al final del archivo de requerimientos
    local file = io.open(paths.requirement, "r")
    local existing_content = ""
    if file then
      existing_content = file:read("*all")
      file:close()
    end

    -- Agregar el contenido del archivo detectado si no existe ya
    if not existing_content:find(auto_detected_file:gsub("%W", "%%%1")) then
      local file = io.open(paths.requirement, "a")
      if file then
        file:write("\n\n## Archivo solicitado automáticamente: " .. auto_detected_file .. "\n\n")
        file:write("```" .. M.detect_file_type(auto_detected_file) .. "\n")
        local file_content = M.read_file_content(auto_detected_file)
        if file_content then
          file:write(file_content)
        else
          file:write("// Error al leer el archivo solicitado: " .. auto_detected_file)
        end
        file:write("\n```\n")
        file:close()
        notify.info("Archivo detectado agregado al contexto: " .. auto_detected_file)
      end
    end
  end

  -- Crear síntesis si no existe
  if vim.fn.filereadable(paths.synthesis) == 0 then
    local synthesis_content = "# Síntesis para " .. (ticket or "ticket actual") .. "\n\n"
    synthesis_content = synthesis_content .. "Este archivo se actualizará automáticamente con la síntesis\n"
    synthesis_content = synthesis_content .. "del contexto y requerimientos del ticket.\n"

    local synthesis_file = io.open(paths.synthesis, "w")
    if synthesis_file then
      synthesis_file:write(synthesis_content)
      synthesis_file:close()
    end
  end

  -- Abrir el archivo de requerimientos en un buffer
  local last_win = vim.api.nvim_get_current_win()
  vim.cmd("edit " .. paths.requirement)

  -- Obtener dimensiones de la ventana actual
  local win_height = vim.api.nvim_win_get_height(0)
  local win_width = vim.api.nvim_win_get_width(0)

  -- Restaurar la ventana anterior
  vim.api.nvim_set_current_win(last_win)

  -- Crear ventana flotante para mostrar los archivos de contexto
  local buf = vim.api.nvim_create_buf(false, true)

  -- Configurar opciones de la ventana flotante
  local width = math.min(120, math.floor(win_width * 0.9))
  local height = math.min(30, math.floor(win_height * 0.8))
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)

  -- Crear la ventana flotante
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded"
  }

  -- Completar el buffer con información sobre los archivos de contexto
  local content = {}
  table.insert(content, "# Archivos de Contexto para " .. (ticket or "Ticket Actual"))
  table.insert(content, "")
  table.insert(content, "## Acciones Disponibles")
  table.insert(content, "")
  table.insert(content, "- `<CR>` en un archivo: abrir el archivo")
  table.insert(content, "- `s` en un archivo: abrir en split horizontal")
  table.insert(content, "- `v` en un archivo: abrir en split vertical")
  table.insert(content, "- `r` en cualquier lugar: actualizar lista")
  table.insert(content, "- `q` o `<Esc>`: cerrar esta ventana")
  table.insert(content, "- `e` o `E`: editar archivo de requerimientos")
  table.insert(content, "- `p` o `P`: editar archivo de proyecto")
  table.insert(content, "- `y` o `Y`: editar archivo de síntesis")
  table.insert(content, "- `c` o `C`: actualizar síntesis con Copilot")
  table.insert(content, "- `f` o `F`: detectar y agregar archivo solicitado")
  table.insert(content, "")
  table.insert(content, "## Archivos Disponibles")
  table.insert(content, "")

  -- Lista de archivos de contexto
  table.insert(content, "1. [Requerimiento] " .. paths.requirement)
  table.insert(content, "2. [Síntesis] " .. paths.synthesis)
  table.insert(content, "3. [Proyecto] " .. paths.project_context)

  -- Verificar si los archivos existen y mostrar su estado
  local function get_file_status(path)
    if vim.fn.filereadable(path) == 1 then
      local file = io.open(path, "r")
      if file then
        local first_line = file:read("*line")
        file:close()
        return "✓ " .. (first_line or "(sin contenido)")
      end
      return "✓ (no se pudo leer)"
    end
    return "✗ (no existe)"
  end

  table.insert(content, "")
  table.insert(content, "## Estado")
  table.insert(content, "")
  table.insert(content, "- Requerimiento: " .. get_file_status(paths.requirement))
  table.insert(content, "- Síntesis: " .. get_file_status(paths.synthesis))
  table.insert(content, "- Proyecto: " .. get_file_status(paths.project_context))

  if auto_detected_file then
    table.insert(content, "")
    table.insert(content, "## Archivo detectado automáticamente")
    table.insert(content, "")
    table.insert(content, "- " .. auto_detected_file)
  end

  -- Añadir las líneas al buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

  -- Crear la ventana con el buffer
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Configurar opciones del buffer
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_name(buf, "CopilotTicket_" .. (ticket or "actual"))

  -- Configurar mapeos de teclas
  local function map(key, action)
    vim.api.nvim_buf_set_keymap(buf, 'n', key, action, { noremap = true, silent = true })
  end

  -- Mapear teclas para cerrar la ventana
  map('q', ':q<CR>')
  map('<Esc>', ':q<CR>')

  -- Mapear teclas para actualizar la lista
  map('r', ':lua require("copilotchatassist.context").copilot_tickets()<CR>')

  -- Mapear teclas para abrir archivos
  map('<CR>', ':lua require("copilotchatassist.context").open_context_file_under_cursor()<CR>')
  map('s', ':lua require("copilotchatassist.context").open_context_file_under_cursor("split")<CR>')
  map('v', ':lua require("copilotchatassist.context").open_context_file_under_cursor("vsplit")<CR>')

  -- Mapear teclas para editar archivos específicos
  map('e', ':edit ' .. paths.requirement .. '<CR>')
  map('E', ':edit ' .. paths.requirement .. '<CR>')
  map('p', ':edit ' .. paths.project_context .. '<CR>')
  map('P', ':edit ' .. paths.project_context .. '<CR>')
  map('y', ':edit ' .. paths.synthesis .. '<CR>')
  map('Y', ':edit ' .. paths.synthesis .. '<CR>')

  -- Mapear tecla para actualizar síntesis
  map('c', ':lua require("copilotchatassist.synthesize").synthesize()<CR>')
  map('C', ':lua require("copilotchatassist.synthesize").synthesize()<CR>')

  -- Mapear tecla para detectar y agregar archivo solicitado
  map('f', ':lua require("copilotchatassist.context").detect_and_add_requested_file()<CR>')
  map('F', ':lua require("copilotchatassist.context").detect_and_add_requested_file()<CR>')

  -- Aplicar sintaxis de resaltado
  vim.cmd([[
    syntax match CopilotTicketHeader /^#.*/
    syntax match CopilotTicketSubheader /^##.*/
    syntax match CopilotTicketItem /^- .*/
    syntax match CopilotTicketPath /\[\(Requerimiento\|Síntesis\|Proyecto\)\] .*/
    hi def link CopilotTicketHeader Title
    hi def link CopilotTicketSubheader Statement
    hi def link CopilotTicketItem Identifier
    hi def link CopilotTicketPath Directory
  ]])

  -- Configurar evento para cuando se cierre la ventana
  vim.api.nvim_command([[autocmd BufWinLeave <buffer> lua vim.api.nvim_win_close(]] .. win .. [[, true)]])

  return win
end

-- Analyze and store global project context
function M.analyze_project_context(requirement)
  -- Iniciar spinner de progreso
  local progress = require("copilotchatassist.utils.progress")
  local spinner_id = "analyze_project_context"
  progress.start_spinner(spinner_id, "Analyzing project context", {
    style = options.get().progress_indicator_style,
    position = "statusline"
  })

  local prompt = require("copilotchatassist.prompts.global_context").default
  local message = prompt .. "\n" .. requirement
  copilot_api.ask(message, {
    headless = true,
    callback = function(response)
      local context_dir = options.get().context_dir
      local project = utils.get_project_name()
      local path = context_dir .. "/" .. project .. "_project_synthesis.md"
      file_utils.write_file(path, response or "")

      -- Mostrar éxito con spinner
      progress.stop_spinner(spinner_id, true)

      -- Iniciar spinner final para mostrar el resultado
      local complete_spinner_id = "project_context_complete"
      progress.start_spinner(complete_spinner_id, "Project context synthesized", {
        style = options.get().progress_indicator_style,
        position = "statusline"
      })

      -- Detener spinner después de 2 segundos
      vim.defer_fn(function()
        progress.stop_spinner(complete_spinner_id, true)
      end, 2000)
    end
  })
end

-- Analyze and store ticket context
function M.analyze_ticket_context(requirement)
  -- Iniciar spinner de progreso
  local progress = require("copilotchatassist.utils.progress")
  local spinner_id = "analyze_ticket_context"
  progress.start_spinner(spinner_id, "Analyzing ticket context", {
    style = options.get().progress_indicator_style,
    position = "statusline"
  })

  local prompt = require("copilotchatassist.prompts.ticket_synthesis").default
  local message = prompt .. "\n" .. requirement
  copilot_api.ask(message, {
    headless = true,
    callback = function(response)
      local paths = M.get_context_paths()
      file_utils.write_file(paths.synthesis, response or "")

      -- Mostrar éxito con spinner
      progress.stop_spinner(spinner_id, true)

      -- Iniciar spinner final para mostrar el resultado
      local complete_spinner_id = "ticket_context_complete"
      progress.start_spinner(complete_spinner_id, "Ticket context synthesized", {
        style = options.get().progress_indicator_style,
        position = "statusline"
      })

      -- Detener spinner después de 2 segundos
      vim.defer_fn(function()
        progress.stop_spinner(complete_spinner_id, true)
      end, 2000)
    end
  })
end

-- Update context wrapper function for init.lua command
function M.update_context()
  local requirement = M.load_requirement() or ""
  local ticket_synthesis = M.load_synthesis() or ""
  local project_synthesis = M.load_project_context() or ""

  -- Ask if ticket context should be updated
  M.ask_should_update_context(requirement, ticket_synthesis, "ticket")
  -- Ask if project context should be updated
  M.ask_should_update_context(requirement, project_synthesis, "project")
end

-- Get project context function for init.lua command
function M.get_project_context()
  local requirement = M.load_requirement() or ""
  M.analyze_project_context(requirement)
end

-- User commands for manual invocation
vim.api.nvim_create_user_command(
  "CopilotProjectContext",
  function()
    local requirement = M.load_requirement() or ""
    M.analyze_project_context(requirement)
  end,
  { desc = "Analyze and store global project context" }
)

vim.api.nvim_create_user_command(
  "CopilotUpdateContext",
  function()
    local requirement = M.load_requirement() or ""
    local ticket_synthesis = M.load_synthesis() or ""
    local project_synthesis = M.load_project_context() or ""

    -- Pregunta si se debe actualizar el contexto del ticket
    M.ask_should_update_context(requirement, ticket_synthesis, "ticket")
    -- Pregunta si se debe actualizar el contexto global del proyecto
    M.ask_should_update_context(requirement, project_synthesis, "project")
  end,
  { desc = "Ask Copilot if context files should be updated and update them if needed" }
)

vim.api.nvim_create_user_command(
  "CopilotTicketContext",
  function()
    local requirement = M.load_requirement() or ""
    M.analyze_ticket_context(requirement)
  end,
  { desc = "Analyze and store ticket context" }
)

function M.ask_should_update_context(requirement, synthesis, type)
  local replacements = {
    requirement = requirement or "",
    context = synthesis or ""
  }
  local prompt = context_prompts.build(context_prompts.update, replacements)
  copilot_api.ask(prompt, {
    headless = true,
    callback = function(response)
      local answer = (response and response.content) or response or ""
      if answer:lower():find("yes") then
        if type == "project" then
          M.analyze_project_context(requirement)
        elseif type == "ticket" then
          M.analyze_ticket_context(requirement)
        end
      else
        log.debug("Context update not required for " .. type .. ".")
      end
    end
  })
end

return M