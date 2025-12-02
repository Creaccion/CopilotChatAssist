local utils = require("copilotchatassist.utils")
local file_utils = require("copilotchatassist.utils.file")
local log = require("copilotchatassist.utils.log")
local options = require("copilotchatassist.options")
local copilot_api = require("copilotchatassist.copilotchat_api")

local M = {}

function M.get_ticket_id()
  local branch = utils.get_current_branch()
  local project = utils.get_project_name()
  local ticket = branch:match("^([A-Z]+%-%d+)")
  if ticket then
    return "jira-" .. ticket .. "-" .. project
  else
    local hash = utils.hash_string(branch)
    return hash .. "-" .. project
  end
end

function M.get_context_paths()
  local context_dir = options.get().context_dir
  file_utils.ensure_dir(context_dir)
  local project = utils.get_project_name()
  local id = M.get_ticket_id()
  return {
    requirement     = context_dir .. "/" .. id .. "_requirement.txt",
    synthesis       = context_dir .. "/" .. id .. "_synthesis.txt",
    project_context = context_dir .. "/" .. project .. "_project_synthesis.txt"
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
  -- Placeholder for project analysis logic
  vim.notify("Analyzing project with requirement:\n" .. requirement, vim.log.levels.INFO)
  -- Aquí puedes llamar a la lógica de análisis, síntesis, etc.
end

function M.copilot_tickets()
  local paths = M.get_context_paths()
  print("Contextos: " .. vim.inspect(paths))
  local requirement = file_utils.read_file(paths.requirement)
  local ticket_synthesis = file_utils.read_file(paths.synthesis)
  local project_synthesis = file_utils.read_file(paths.project_context)

  -- Si no hay requerimiento, solicitarlo al usuario
  if not (requirement and #requirement > 10) then
    local branch = utils.get_current_branch()
    local ticket = branch:match("^([A-Z]+%-%d+)")
    if ticket then
      local jira_url = "https://pagerduty.atlassian.net/browse/" .. ticket
      vim.fn.jobstart({ "open", jira_url }, { detach = true })
      vim.notify("Jira ticket detected: " .. ticket .. ". Paste the requirement from Jira in the buffer.",
        vim.log.levels.INFO)
    else
      vim.notify("No Jira ticket detected. Personal project context will be used.", vim.log.levels.INFO)
    end
    M.input_requirement()
    return
  end

  -- Si falta síntesis de ticket, generarla
  if not (ticket_synthesis and #ticket_synthesis > 10) then
    vim.notify("Generating ticket synthesis...", vim.log.levels.INFO)
    M.analyze_ticket_context(requirement)
    ticket_synthesis = file_utils.read_file(paths.synthesis)
  end

  -- Si falta síntesis de proyecto, generarla y espera a que esté lista antes de continuar
  if not (project_synthesis and #project_synthesis > 10) then
    vim.notify("Generating project synthesis...", vim.log.levels.INFO)
    M.analyze_project_context(requirement)
    -- Espera a que el contexto global esté listo y vuelve a intentar la combinación
    vim.defer_fn(function()
      -- Recarga el contexto global
      local updated_project_synthesis = file_utils.read_file(paths.project_context)
      if updated_project_synthesis and #updated_project_synthesis > 10 then
        -- Vuelve a intentar la combinación de contextos
        M.copilot_tickets()
      else
        vim.notify("Project synthesis not ready yet. Please try again in a moment.", vim.log.levels.WARN)
      end
    end, 1500) -- espera 1.5 segundos antes de reintentar
    return
  end

  -- Combinar los contextos existentes
  local context_parts = {}
  if requirement and #requirement > 10 then
    table.insert(context_parts, "-- Requirement Context --\n" .. requirement)
  end
  if ticket_synthesis and #ticket_synthesis > 10 then
    table.insert(context_parts, "-- Ticket Synthesis --\n" .. ticket_synthesis)
  end
  if project_synthesis and #project_synthesis > 10 then
    table.insert(context_parts, "-- Project Synthesis --\n" .. project_synthesis)
  end

  print("# context_parts: " .. #context_parts)
  print("context_parts: " .. vim.inspect(context_parts))
  if #context_parts > 0 then
    print("Pre concat")
    local full_context = table.concat(context_parts, "\n\n")
    vim.notify("Loaded combined context from available files.", vim.log.levels.INFO)
    copilot_api.ask(full_context)
    return
  end

  vim.notify("No context files found. Please create requirement or synthesis.", vim.log.levels.WARN)
end

--
-- Analyze and store global project context
function M.analyze_project_context(requirement)
  local prompt = require("copilotchatassist.prompts.global_context").default
  local message = prompt .. "\n" .. requirement
  copilot_api.ask(message, {
    headless = true,
    callback = function(response)
      local context_dir = options.get().context_dir
      local project = utils.get_project_name()
      local path = context_dir .. "/" .. project .. "_project_synthesis.txt"
      file_utils.write_file(path, response or "")
      vim.notify("Project context synthesis saved: " .. path, vim.log.levels.INFO)
    end
  })
end

-- Analyze and store ticket context
function M.analyze_ticket_context(requirement)
  local prompt = require("copilotchatassist.prompts.ticket_synthesis").default
  local message = prompt .. "\n" .. requirement
  copilot_api.ask(message, {
    headless = true,
    callback = function(response)
      local paths = M.get_context_paths()
      file_utils.write_file(paths.synthesis, response or "")
      vim.notify("Ticket context synthesis saved: " .. paths.synthesis, vim.log.levels.INFO)
    end
  })
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

local copilot_api = require("copilotchatassist.copilotchat_api")

function M.ask_should_update_context(requirement, synthesis, type)
  local copilot_api = require("copilotchatassist.copilotchat_api")
  local prompt_template = require("copilotchatassist.prompts.context_update").default
  local prompt = prompt_template
      :gsub("<requirement>", requirement or "")
      :gsub("<context>", synthesis or "")
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
        vim.notify("Context update not required for " .. type .. ".", vim.log.levels.INFO)
      end
    end
  })
end

-- function M.load_existing_context()
--   local requirement = M.load_requirement()
--   local synthesis = M.load_synthesis()
--   local context_dir = options.get().context_dir
--   local project = utils.get_project_name()
--   local project_synthesis_path = context_dir .. "_" .. project .. "_project_synthesis.txt"
--   local project_synthesis = file_utils.read_file(project_synthesis_path)
--
--   if requirement and #requirement > 10 then
--     table.insert(context_parts, "-- Requirement Context --\n" .. requirement)
--   end
--   if ticket_synthesis and #ticket_synthesis > 10 then
--     table.insert(context_parts, "-- Ticket Synthesis --\n" .. ticket_synthesis)
--   end
--   if project_synthesis and #project_synthesis > 10 then
--     table.insert(context_parts, "-- Project Synthesis --\n" .. project_synthesis)
--   end
-- end

return M

-- Context-related functions for CopilotChat
-- local utils = require("copilotchatassist.utils")
-- local CopilotChat = require("CopilotChat")
-- local M = {}
--
-- -- Load previously saved synthesis into current buffer (plain insert)
-- function M.load_context_as_prompt()
--   local context_dir = utils.get_context_dir()
--   local context_path = context_dir .. utils.get_project_name() .. "_synthesis.md"
--   if vim.fn.filereadable(context_path) == 1 then
--     local lines = {}
--     for line in io.lines(context_path) do
--       table.insert(lines, line)
--     end
--     vim.api.nvim_put(lines, "c", true, true)
--     vim.notify("Contexto de CopilotChat cargado desde: " .. context_path)
--   else
--     vim.notify("No existe síntesis previa para el proyecto.", vim.log.levels.WARN)
--   end
-- end
--
-- -- Read or (if missing) generate a global context
-- function M.get_global_context()
--   local global_path = utils.get_context_dir() .. utils.get_project_name() .. "_global.md"
--   local f = io.open(global_path, "r")
--   if f then
--     local content = f:read("*a")
--     f:close()
--     return content or ""
--   end
--
--   -- If not exists, request generation asynchronously
--   local prompt = [[
-- Analiza el proyecto detectando automáticamente el stack tecnológico principal según los archivos presentes: ##files://glob/**.*
--
-- - Si detectas más de un stack, pregunta cuál debe usarse.
-- - Incluye patrones de archivos relevantes, archivos de infraestructura y contenedores si existen.
-- - Considera los cambios en el branch actual: ##git://diff/main..HEAD.
-- - Si necesitas más información, solicita la estructura del proyecto o acceso a archivos específicos.
--
-- Proporciona:
-- - Resumen del propósito del proyecto
-- - Estructura general y organización de componentes
-- - Áreas de mejora en arquitectura, código y buenas prácticas
-- - Análisis de dependencias y recomendaciones
-- - Sugerencias para documentación y contexto
-- - Recomendaciones de CI/CD (por ejemplo: Buildkite, CircleCI)
-- - Mejores prácticas de seguridad y rendimiento
-- - Otros aspectos relevantes
--
-- Mantén este contexto para futuras consultas.
-- Responde exclusivamente en español a menos que el usuario pida explícitamente otro idioma.
--
-- ]]
--   CopilotChat.ask(prompt, {
--     callback = function(response)
--       local content = (response and response.content) or response or ""
--       local f2 = io.open(global_path, "w")
--       if f2 then
--         f2:write(content)
--         f2:close()
--         vim.notify("Contexto global generado y guardado en: " .. global_path)
--       end
--     end,
--   })
--   vim.notify("Generando contexto global, reintenta el comando luego.")
--   return nil
-- end
--
-- -- Project context (initial analysis)
-- function M.project_context_prompt()
--   local project_name = utils.get_project_name()
--   local context_dir = utils.get_context_dir()
--   CopilotChat.open()
--   vim.defer_fn(function()
--     local buf = vim.api.nvim_get_current_buf()
--     local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
--     if #lines <= 3 and lines[1] and lines[1]:match("^👤 Usuario: ") then
--       local context_path = context_dir .. project_name .. "_synthesis.md"
--       local prompt
--       if vim.fn.filereadable(context_path) == 1 then
--         local file_lines = {}
--         for line in io.lines(context_path) do
--           table.insert(file_lines, line)
--         end
--         prompt = table.concat(file_lines, "\n")
--       else
--         prompt = [[
-- Analiza el proyecto detectando automáticamente el stack tecnológico principal según los archivos presentes: ##files://glob/**.*
--
-- - Si detectas más de un stack, pregunta cuál debe usarse.
-- - Incluye patrones de archivos relevantes, archivos de infraestructura y contenedores si existen.
-- - Considera los cambios en el branch actual: ##git://diff/main..HEAD.
-- - Si necesitas más información, solicita la estructura del proyecto o acceso a archivos específicos.
--
-- Proporciona:
-- - Resumen del propósito del proyecto
-- - Estructura general y organización de componentes
-- - Áreas de mejora en arquitectura, código y buenas prácticas
-- - Análisis de dependencias y recomendaciones
-- - Sugerencias para documentación y contexto
-- - Recomendaciones de CI/CD (por ejemplo: Buildkite, CircleCI)
-- - Mejores prácticas de seguridad y rendimiento
-- - Otros aspectos relevantes
--
-- Mantén este contexto para futuras consultas.
-- Responde exclusivamente en español a menos que el usuario pida explícitamente otro idioma.
-- ]]
--       end
--       CopilotChat.ask(prompt)
--       vim.notify("Contexto inicial insertado en CopilotChat.")
--     else
--       vim.notify("Buffer de chat ya contiene contenido, no se sobrescribe.", vim.log.levels.INFO)
--     end
--   end, 100)
-- end
--
-- -- Extract ticket name from branch (e.g., feature/PD-1234-foo)
-- function M.extract_ticket_name()
--   local branch = utils.get_current_branch()
--   local project_name = utils.get_project_name()
--   if not branch or branch == "" then
--     return project_name
--   end
--   local ticket = branch:match("([A-Z]+%-%d+)")
--   if ticket and ticket ~= "" then
--     return ticket
--   end
--   return project_name .. "-" .. branch:sub(1, 8)
-- end
--
-- function M.extract_ticket_name()
--   local branch = utils.get_current_branch()
--   local project_name = utils.get_project_name()
--   if not branch or branch == "" then
--     return project_name .. "-" .. os.date("%Y%m%d%H%M%S") -- Generate unique ID based on timestamp
--   end
--   local ticket = branch:match("([A-Z]+%-%d+)")
--   if ticket and ticket ~= "" then
--     return ticket
--   end
--   -- Generate unique ID if no ticket is found
--   return project_name .. "-" .. os.date("%Y%m%d%H%M%S")
-- end
--
-- function M.get_requirement_from_commit()
--   local handle = io.popen("git log -1 --pretty=%B 2>/dev/null")
--   if not handle then return nil end
--   local msg = handle:read("*a") or ""
--   handle:close()
--   return (msg:gsub("^%s+", ""):gsub("%s+$", ""))
-- end
--
-- function M.get_jira_link(ticket)
--   return "https://pagerduty.atlassian.net/browse/" .. ticket
-- end
--
-- -- Read requirement file or prompt user to create it
-- function M.get_or_ask_requirement(ticket)
--   local context_dir = utils.get_context_dir()
--   local req_path = context_dir .. ticket .. "_requirement.txt"
--
--   -- Check if the requirement file already exists
--   local f = io.open(req_path, "r")
--   if f then
--     local content = f:read("*a") or ""
--     f:close()
--     if content ~= "" then
--       return content
--     end
--   end
--
--   -- If no ticket (personal project), skip Jira and create an empty file
--   if not ticket:match("^[A-Z]+%-%d+$") then
--     vim.notify("Proyecto personal detectado. No se requiere Jira.", vim.log.levels.INFO)
--     local f2 = io.open(req_path, "w")
--     if f2 then
--       f2:write("Requerimiento no especificado para proyecto personal.")
--       f2:close()
--     end
--     return "Requerimiento no especificado para proyecto personal."
--   end
--
--   -- Open Jira link for non-personal projects
--   local jira_link = M.get_jira_link(ticket)
--   vim.fn.jobstart({ "open", jira_link }, { detach = true })
--   vim.notify(
--     "Pega el requerimiento de Jira en el nuevo buffer y guarda: " .. jira_link,
--     vim.log.levels.INFO
--   )
--   vim.cmd("vsplit " .. req_path)
--   vim.cmd("redraw")
--   vim.cmd("echo 'Guarda el archivo y re-ejecuta :CopilotTickets'")
--   return nil
-- end
--
-- function M.save_synthesis(ticket, content)
--   local context_dir = utils.get_context_dir()
--   local path = context_dir .. ticket .. "_synthesis.md"
--   local f = io.open(path, "w")
--   if not f then
--     vim.notify("No se pudo guardar síntesis en: " .. path, vim.log.levels.ERROR)
--     return
--   end
--   f:write(content)
--   f:close()
-- end
--
-- function M.get_ticket_context(ticket)
--   local context_dir = utils.get_context_dir()
--   local synth_path = context_dir .. ticket .. "_synthesis.md"
--   print(vim.inspect(synth_path))
--   local f = io.open(synth_path, "r")
--   if f then
--     local content = f:read("*a") or ""
--     f:close()
--     if content ~= "" then
--       return content
--     end
--   end
--   return nil
-- end
--
-- -- Main ticket synthesis command
-- function M.ticket_context_prompt()
--   local branch = utils.get_current_branch()
--   local ticket = M.extract_ticket_name()
--   if not ticket then
--     vim.notify("No se pudo identificar el ticket (rama: " .. (branch or "?") .. ")", vim.log.levels.ERROR)
--     return
--   end
--
--   local existing = M.get_ticket_context(ticket)
--   if existing then
--     CopilotChat.open()
--     CopilotChat.ask(existing)
--     vim.notify("Contexto del ticket cargado (reutilizado).")
--     return
--   end
--
--   local requirement = M.get_or_ask_requirement(ticket)
--   if not requirement then
--     -- User must paste requirement first
--     return
--   end
--
--   local diff = M.get_diff_for_ticket()
--   local global_context = M.get_global_context()
--   if not global_context or global_context == "" then
--     vim.notify("Esperando generación de contexto global. Reintenta luego.", vim.log.levels.WARN)
--     return
--   end
--
--   local jira_link = M.get_jira_link(ticket)
--
--   local synthesis = string.format([[
-- %s
--
-- # Ticket: %s
--
-- - **Rama:** %s
-- - **Requerimiento:** %s
-- - **Enlace a Jira:** %s
--
-- ## Cambios en esta rama
--
-- %s
--
-- ---
--
-- Es importante que definas una lista de tareas para ordenar el trabajo del ticket e ir registrando avances.
-- Cada vez que avances, indica qué tareas se cerraron. Si envías nuevamente la lista, se actualizará.
-- Mantén las tareas como lista con checks, número, título y breve descripción.
--
-- Este contexto se mantendrá abierto hasta que la rama sea mergeada a main.
-- Responde exclusivamente en español a menos que el usuario pida explícitamente otro idioma.
-- ]], global_context, ticket, branch or "?", requirement, jira_link, diff ~= "" and diff or "(Sin cambios detectados)")
--
--   M.save_synthesis(ticket, synthesis)
--   vim.notify("Síntesis de ticket guardada.")
--   CopilotChat.open()
--   CopilotChat.ask(synthesis)
-- end
--
-- function M.get_diff_for_ticket()
--   -- Return a concise name-status diff; fallback to main if origin/main unavailable
--   local cmd = "git diff --name-status origin/main..HEAD 2>/dev/null"
--   local handle = io.popen(cmd)
--   if not handle then return "" end
--   local diff = handle:read("*a") or ""
--   handle:close()
--   return diff
-- end
--
-- function M.enrich_and_save_prompt(ticket, req_path, synth_path, extra_info)
--   local f = io.open(req_path, "r")
--   local requirement = f and (f:read("*a") or "") or ""
--   if f then f:close() end
--
--   local branch = utils.get_current_branch()
--   local jira_link = M.get_jira_link(ticket)
--   local global_context = M.get_global_context() or ""
--   local diff = M.get_diff_for_ticket()
--
--   local prompt = string.format([[
-- %s
--
-- # Ticket: %s
--
-- - **Rama:** %s
-- - **Enlace a Jira:** %s
--
-- ## Requerimiento
-- %s
--
-- ## Cambios en esta rama
-- %s
--
-- ## Tareas pendientes
-- %s
--
-- ## Problemas por solucionar
-- %s
--
-- ---
-- (Esta síntesis se actualizará; mantén la lista de tareas numerada con checks.)
-- ]], global_context, ticket, branch or "?", jira_link, requirement ~= "" and requirement or "(Pendiente)", diff, extra_info.tasks or "", extra_info.issues or "")
--
--   local f2 = io.open(synth_path, "w")
--   if f2 then
--     f2:write(prompt)
--     f2:close()
--   else
--     vim.notify("No se pudo escribir síntesis enriquecida.", vim.log.levels.ERROR)
--   end
-- end
--
-- function M.on_buf_leave(args)
--   local ticket = M.extract_ticket_name()
--   local context_dir = utils.get_context_dir()
--   local req_path = context_dir .. ticket .. "_requirement.txt"
--   local synth_path = context_dir .. ticket .. "_synthesis.md"
--   local buf = args.buf
--   if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
--   vim.ui.select(
--     { "Sí", "No" },
--     { prompt = "¿Sintetizar y guardar requerimiento/ticket?" },
--     function(choice)
--       if choice == "Sí" then
--         M.enrich_and_save_prompt(ticket, req_path, synth_path, { tasks = "", issues = "" })
--         vim.notify("Prompt enriquecido guardado para " .. ticket)
--       end
--     end
--   )
-- end
--
-- return M
