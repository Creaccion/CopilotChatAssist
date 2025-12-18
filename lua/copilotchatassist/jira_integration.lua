-- Módulo de integración con Jira para CopilotChatAssist
-- Permite obtener información de tickets, actualizar tickets y usar información como contexto

local curl = require("copilotchatassist.utils.curl") -- Utilizaremos esta utilidad para las llamadas HTTP
local log = require("copilotchatassist.utils.log")
local notify = require("copilotchatassist.utils.notify")
local context = require("copilotchatassist.context")
local file_utils = require("copilotchatassist.utils.file")
local i18n = require("copilotchatassist.i18n")
local base64 = require("copilotchatassist.utils.base64") -- Crearemos esta utilidad para codificar credenciales
local options = require("copilotchatassist.options")

-- Módulo principal
local M = {}

-- Estado del módulo
M.state = {
  connected = false,
  current_ticket = nil,
  credentials_loaded = false,
  cached_tickets = {},
  cached_projects = {},
}

-- Configuración por defecto
M.config = {
  host = nil,             -- URL de la instancia Jira (ej: "https://tuempresa.atlassian.net")
  email = nil,            -- Email de la cuenta Jira
  api_token = nil,        -- Token API de Jira (https://id.atlassian.com/manage-profile/security/api-tokens)
  project_key = nil,      -- Clave del proyecto por defecto (ej: "PROJ")
  auto_load = true,       -- Cargar automáticamente ticket al cambiar de rama
  auto_update = false,    -- Actualizar Jira automáticamente al guardar contexto
  use_keyring = true,     -- Usar el llavero del sistema para guardar credenciales
  cache_timeout = 300,    -- Tiempo de caché en segundos (5 minutos)
  request_timeout = 10,   -- Tiempo máximo para peticiones HTTP en segundos
  max_results = 20,       -- Número máximo de resultados para búsquedas
  context_format = "detailed" -- Formato del contexto extraído: "simple", "detailed"
}

-- Rutas para almacenamiento local
local function get_storage_paths()
  local cache_dir = vim.fn.stdpath("cache") .. "/copilotchatassist/jira"
  vim.fn.mkdir(cache_dir, "p")

  return {
    cache_dir = cache_dir,
    credentials = cache_dir .. "/credentials.json",
    cache = cache_dir .. "/cache.json",
    config = cache_dir .. "/config.json",
  }
end

-- Guardar configuración
local function save_config()
  local paths = get_storage_paths()

  -- No guardar credenciales sensibles en la configuración directamente
  local safe_config = vim.deepcopy(M.config)
  safe_config.email = nil
  safe_config.api_token = nil

  file_utils.write_file(paths.config, vim.fn.json_encode(safe_config))
end

-- Cargar configuración
local function load_config()
  local paths = get_storage_paths()
  local config_json = file_utils.read_file(paths.config)

  if config_json then
    local ok, config = pcall(vim.fn.json_decode, config_json)
    if ok and config then
      for k, v in pairs(config) do
        M.config[k] = v
      end
    end
  end
end

-- Guardar credenciales (cifradas con una clave simple - en producción usar keyring)
local function save_credentials()
  if not M.config.email or not M.config.api_token then
    return false
  end

  local paths = get_storage_paths()
  local credentials = {
    email = M.config.email,
    api_token = M.config.api_token
  }

  -- En una implementación real, usaríamos el llavero del sistema
  -- Por ahora, hacemos un cifrado simple para no guardar en texto plano
  local encoded = base64.encode(vim.fn.json_encode(credentials))
  file_utils.write_file(paths.credentials, encoded)

  return true
end

-- Cargar credenciales
local function load_credentials()
  local paths = get_storage_paths()
  local encoded = file_utils.read_file(paths.credentials)

  if not encoded then
    return false
  end

  local decoded = base64.decode(encoded)
  local ok, credentials = pcall(vim.fn.json_decode, decoded)

  if not ok or not credentials then
    return false
  end

  M.config.email = credentials.email
  M.config.api_token = credentials.api_token
  M.state.credentials_loaded = true

  return true
end

-- Obtener encabezados HTTP para API de Jira
local function get_headers()
  if not M.config.email or not M.config.api_token then
    log.error("Credenciales de Jira no configuradas")
    return nil
  end

  local auth = base64.encode(M.config.email .. ":" .. M.config.api_token)

  return {
    Authorization = "Basic " .. auth,
    ["Content-Type"] = "application/json",
    Accept = "application/json"
  }
end

-- Hacer una petición a la API de Jira
function M.api_request(method, endpoint, data, callback)
  if not M.config.host then
    log.error("Host de Jira no configurado")
    if callback then callback(false, "Host de Jira no configurado") end
    return
  end

  local headers = get_headers()
  if not headers then
    log.error("No se pudieron obtener los encabezados HTTP")
    if callback then callback(false, "Error de autenticación") end
    return
  end

  local url = M.config.host
  if not url:match("/$") then url = url .. "/" end
  url = url .. "rest/api/3/" .. endpoint

  log.debug("Realizando petición a Jira: " .. method .. " " .. url)

  local options = {
    url = url,
    method = method,
    headers = headers,
    timeout = M.config.request_timeout * 1000
  }

  if data and (method == "POST" or method == "PUT") then
    options.body = vim.fn.json_encode(data)
  end

  -- Realizar petición HTTP
  curl.request(options, function(response)
    if response.status >= 200 and response.status < 300 then
      local ok, json_data = pcall(vim.fn.json_decode, response.body)
      if not ok then
        log.error("Error al procesar respuesta JSON de Jira")
        if callback then callback(false, "Error al procesar respuesta") end
        return
      end

      if callback then callback(true, json_data) end
    else
      log.error("Error en petición a Jira: " .. response.status)
      if callback then callback(false, "Error " .. response.status) end
    end
  end)
end

-- Verificar conexión con Jira
function M.check_connection(callback)
  M.api_request("GET", "myself", nil, function(success, data)
    if success then
      M.state.connected = true
      log.info("Conexión a Jira establecida como: " .. data.displayName)
      if callback then callback(true, data) end
    else
      M.state.connected = false
      log.error("No se pudo conectar a Jira")
      if callback then callback(false, data) end
    end
  end)
end

-- Obtener detalles de un ticket
function M.get_ticket_details(ticket_id, callback)
  -- Verificar caché primero
  if M.state.cached_tickets[ticket_id] then
    local cached = M.state.cached_tickets[ticket_id]
    local now = os.time()

    if now - cached.timestamp < M.config.cache_timeout then
      log.debug("Usando datos en caché para ticket " .. ticket_id)
      if callback then callback(true, cached.data) end
      return
    end
  end

  -- No está en caché o caducó, hacer petición
  M.api_request("GET", "issue/" .. ticket_id, nil, function(success, data)
    if success then
      -- Guardar en caché
      M.state.cached_tickets[ticket_id] = {
        data = data,
        timestamp = os.time()
      }

      if callback then callback(true, data) end
    else
      if callback then callback(false, data) end
    end
  end)
end

-- Buscar tickets con JQL
function M.search_tickets(jql, callback)
  local data = {
    jql = jql,
    maxResults = M.config.max_results,
    fields = {
      "summary",
      "status",
      "assignee",
      "priority",
      "description",
      "created",
      "updated",
      "issuetype"
    }
  }

  M.api_request("POST", "search", data, function(success, response)
    if success then
      if callback then callback(true, response) end
    else
      if callback then callback(false, response) end
    end
  end)
end

-- Actualizar un ticket
function M.update_ticket(ticket_id, fields, callback)
  local data = {
    fields = fields
  }

  M.api_request("PUT", "issue/" .. ticket_id, data, function(success, response)
    if success then
      -- Invalidar caché para este ticket
      if M.state.cached_tickets[ticket_id] then
        M.state.cached_tickets[ticket_id] = nil
      end

      if callback then callback(true, response) end
    else
      if callback then callback(false, response) end
    end
  end)
end

-- Añadir comentario a un ticket
function M.add_comment(ticket_id, comment, callback)
  local data = {
    body = {
      type = "doc",
      version = 1,
      content = {
        {
          type = "paragraph",
          content = {
            {
              type = "text",
              text = comment
            }
          }
        }
      }
    }
  }

  M.api_request("POST", "issue/" .. ticket_id .. "/comment", data, function(success, response)
    if success then
      if callback then callback(true, response) end
    else
      if callback then callback(false, response) end
    end
  end)
end

-- Registrar tiempo en un ticket
function M.log_time(ticket_id, time_spent, comment, callback)
  local data = {
    timeSpent = time_spent, -- Formato: "1h 30m"
    comment = {
      type = "doc",
      version = 1,
      content = {
        {
          type = "paragraph",
          content = {
            {
              type = "text",
              text = comment or "Tiempo registrado desde Neovim"
            }
          }
        }
      }
    }
  }

  M.api_request("POST", "issue/" .. ticket_id .. "/worklog", data, function(success, response)
    if success then
      if callback then callback(true, response) end
    else
      if callback then callback(false, response) end
    end
  end)
end

-- Detectar ID de ticket desde nombre de rama
function M.detect_ticket_from_branch()
  local branch = vim.fn.system("git branch --show-current"):gsub("%s+$", "")

  -- Patrón común: PROJECT-123-descripcion
  local pattern = "([A-Z]+%-[0-9]+)"
  local ticket_id = branch:match(pattern)

  if ticket_id then
    log.debug("Ticket detectado en rama: " .. ticket_id)
    return ticket_id
  end

  return nil
end

-- Formatear ticket para mostrar
function M.format_ticket_summary(ticket)
  if not ticket then return "No hay información de ticket disponible" end

  local summary = "# " .. ticket.key .. ": " .. ticket.fields.summary .. "\n\n"

  summary = summary .. "**Tipo:** " .. ticket.fields.issuetype.name .. "\n"
  summary = summary .. "**Estado:** " .. ticket.fields.status.name .. "\n"

  if ticket.fields.assignee then
    summary = summary .. "**Asignado a:** " .. ticket.fields.assignee.displayName .. "\n"
  end

  summary = summary .. "**Prioridad:** " .. ticket.fields.priority.name .. "\n"
  summary = summary .. "**Creado:** " .. ticket.fields.created:sub(1, 10) .. "\n"
  summary = summary .. "**Actualizado:** " .. ticket.fields.updated:sub(1, 10) .. "\n\n"

  summary = summary .. "## Descripción\n\n"

  -- Simplificar la descripción (en una implementación real, se debería procesar Atlassian Document Format)
  if ticket.fields.description then
    if type(ticket.fields.description) == "string" then
      summary = summary .. ticket.fields.description
    elseif type(ticket.fields.description) == "table" and ticket.fields.description.content then
      summary = summary .. "Ver descripción completa en Jira"
    end
  else
    summary = summary .. "*Sin descripción*"
  end

  return summary
end

-- Cargar ticket como contexto
function M.load_ticket_as_context(ticket_id, callback)
  M.get_ticket_details(ticket_id, function(success, ticket)
    if not success then
      log.error("Error al cargar ticket: " .. (ticket or "desconocido"))
      notify.error("Error al cargar ticket de Jira: " .. ticket_id)
      if callback then callback(false) end
      return
    end

    -- Formatear ticket para contexto
    local ticket_content = M.format_ticket_summary(ticket)

    -- Guardar en archivo de contexto
    local paths = context.get_context_paths()
    file_utils.write_file(paths.requirement, ticket_content)

    -- Actualizar estado
    M.state.current_ticket = ticket_id

    -- Notificar al usuario
    notify.info("Ticket cargado como contexto: " .. ticket_id)

    -- Si está configurado, generar síntesis automáticamente
    if M.config.auto_generate_synthesis then
      context.analyze_ticket_context(ticket_content)
    end

    if callback then callback(true, ticket) end
  end)
end

-- Crear comandos de Neovim
function M.create_commands()
  vim.api.nvim_create_user_command("JiraConnect", function()
    notify.info("Conectando con Jira...")
    M.check_connection(function(success, data)
      if success then
        notify.success("Conectado a Jira como: " .. data.displayName)
      else
        notify.error("Error al conectar con Jira")
      end
    end)
  end, { desc = "Comprobar conexión con Jira" })

  vim.api.nvim_create_user_command("JiraTicket", function(opts)
    notify.info("Cargando ticket " .. opts.args)
    M.load_ticket_as_context(opts.args)
  end, { nargs = 1, desc = "Cargar ticket de Jira como contexto" })

  vim.api.nvim_create_user_command("JiraDetect", function()
    local ticket_id = M.detect_ticket_from_branch()
    if ticket_id then
      notify.info("Ticket detectado: " .. ticket_id .. ". Cargando...")
      M.load_ticket_as_context(ticket_id)
    else
      notify.warn("No se detectó ningún ticket en la rama actual")
    end
  end, { desc = "Detectar y cargar ticket de la rama actual" })

  vim.api.nvim_create_user_command("JiraComment", function(opts)
    if not M.state.current_ticket then
      notify.error("No hay ticket actual cargado")
      return
    end

    notify.info("Añadiendo comentario a " .. M.state.current_ticket)
    M.add_comment(M.state.current_ticket, opts.args, function(success)
      if success then
        notify.success("Comentario añadido correctamente")
      else
        notify.error("Error al añadir comentario")
      end
    end)
  end, { nargs = 1, desc = "Añadir comentario al ticket actual" })

  vim.api.nvim_create_user_command("JiraTime", function(opts)
    if not M.state.current_ticket then
      notify.error("No hay ticket actual cargado")
      return
    end

    local parts = vim.split(opts.args, " ", { plain = true })
    local time = parts[1]
    local comment = table.concat(parts, " ", 2)

    notify.info("Registrando " .. time .. " en " .. M.state.current_ticket)
    M.log_time(M.state.current_ticket, time, comment, function(success)
      if success then
        notify.success("Tiempo registrado correctamente")
      else
        notify.error("Error al registrar tiempo")
      end
    end)
  end, { nargs = "+", desc = "Registrar tiempo en el ticket actual (ej: JiraTime 1h 30m Implementación)" })

  vim.api.nvim_create_user_command("JiraSearch", function(opts)
    notify.info("Buscando tickets...")
    M.search_tickets(opts.args, function(success, response)
      if not success then
        notify.error("Error en la búsqueda")
        return
      end

      if response.total == 0 then
        notify.warn("No se encontraron tickets")
        return
      end

      -- Crear buffer con resultados
      local buf = vim.api.nvim_create_buf(false, true)
      local lines = {}

      table.insert(lines, "# Resultados de búsqueda en Jira")
      table.insert(lines, "")
      table.insert(lines, "Encontrados " .. response.total .. " tickets.")
      table.insert(lines, "")

      for _, issue in ipairs(response.issues) do
        local status = issue.fields.status.name
        local line = issue.key .. " | " .. status .. " | " .. issue.fields.summary
        table.insert(lines, line)
      end

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
      vim.api.nvim_buf_set_option(buf, "modifiable", false)

      -- Abrir en split
      vim.cmd("vsplit")
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)

      -- Mapeo para cargar ticket con <Enter>
      vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
        callback = function()
          local line = vim.api.nvim_get_current_line()
          local ticket_id = line:match("([A-Z]+%-%d+)")
          if ticket_id then
            vim.cmd("JiraTicket " .. ticket_id)
          end
        end,
        noremap = true,
        silent = true,
        desc = "Cargar ticket seleccionado"
      })

      notify.success("Búsqueda completada")
    end)
  end, { nargs = 1, desc = "Buscar tickets en Jira (ej: JiraSearch \"project = PROJ AND status = 'In Progress'\")" })

  vim.api.nvim_create_user_command("JiraSetup", function()
    -- Solicitar parámetros de configuración interactivamente
    vim.ui.input({ prompt = "URL de Jira (ej: https://empresa.atlassian.net): " }, function(host)
      if not host or host == "" then return end
      M.config.host = host

      vim.ui.input({ prompt = "Email: " }, function(email)
        if not email or email == "" then return end
        M.config.email = email

        vim.ui.input({ prompt = "API Token: " }, function(token)
          if not token or token == "" then return end
          M.config.api_token = token

          vim.ui.input({ prompt = "Proyecto por defecto (ej: PROJ): " }, function(project)
            M.config.project_key = project

            save_config()
            save_credentials()

            notify.info("Configuración guardada. Comprobando conexión...")
            M.check_connection(function(success)
              if success then
                notify.success("Configuración completa y verificada")
              else
                notify.error("Error al conectar con la configuración proporcionada")
              end
            end)
          end)
        end)
      end)
    end)
  end, { desc = "Configurar integración con Jira" })
end

-- Inicializar autocomandos
function M.setup_autocmds()
  if M.config.auto_load then
    -- Autocomando para cargar ticket al cambiar de rama
    local group = vim.api.nvim_create_augroup("JiraIntegration", { clear = true })

    vim.api.nvim_create_autocmd("DirChanged", {
      pattern = "*",
      group = group,
      callback = function()
        -- Verificar si estamos en un repositorio git
        local is_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):gsub("%s+$", "") == "true"
        if not is_git then return end

        local ticket_id = M.detect_ticket_from_branch()
        if ticket_id and ticket_id ~= M.state.current_ticket then
          log.info("Rama cambiada, detectado ticket: " .. ticket_id)
          M.load_ticket_as_context(ticket_id)
        end
      end
    })
  end
end

-- Cargar módulo
function M.setup(opts)
  -- Cargar configuración guardada
  load_config()

  -- Aplicar opciones proporcionadas
  if opts then
    for k, v in pairs(opts) do
      M.config[k] = v
    end
  end

  -- Guardar configuración actualizada
  save_config()

  -- Intentar cargar credenciales guardadas
  load_credentials()

  -- Crear comandos
  M.create_commands()

  -- Configurar autocomandos
  M.setup_autocmds()

  -- Si tenemos credenciales, verificar conexión
  if M.config.host and M.config.email and M.config.api_token then
    M.check_connection()
  end

  -- Registrar opción para añadir código a options.lua
  if options.jira == nil then
    options.jira = M.config
  end

  log.info("Módulo de integración con Jira inicializado")
end

return M