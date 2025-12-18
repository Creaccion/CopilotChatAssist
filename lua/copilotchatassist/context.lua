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
            vim.notify("No Jira ticket detected. Personal project context will be used.", vim.log.levels.INFO)
          end
          M.input_requirement()
          return
        end

        if not (ticket_synthesis and #ticket_synthesis > 10) then
          vim.notify("Generating ticket synthesis...", vim.log.levels.INFO)
          M.analyze_ticket_context(requirement)
          ticket_synthesis = file_utils.read_file(paths.synthesis)
        end

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
        local function combine_contexts()
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
            notify.info(i18n.t("context.context_loaded_combined"))
            copilot_api.ask(full_context)
            return
          end

          local i18n = require("copilotchatassist.i18n")
          local notify = require("copilotchatassist.utils.notify")
          notify.warn(i18n.t("context.no_context_files"), {force = true})
        end

        -- Actualiza ticket y proyecto en serie, luego combina
        M.update_context_with_progress(requirement, paths.synthesis, function()
          M.update_context_with_progress(requirement, paths.project_context, function()
            combine_contexts()
          end)
        end)
      else
        vim.notify("Context creation cancelled by user.", vim.log.levels.INFO)
        return
      end
    end)
    return
  end

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
  local function combine_contexts()
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
      notify.info(i18n.t("context.context_loaded_combined"))
      copilot_api.ask(full_context)
      return
    end

    local i18n = require("copilotchatassist.i18n")
    local notify = require("copilotchatassist.utils.notify")
    notify.warn(i18n.t("context.no_context_files"), {force = true})
  end

  -- Actualiza ticket y proyecto en serie, luego combina
  M.update_context_with_progress(requirement, paths.synthesis, function()
    M.update_context_with_progress(requirement, paths.project_context, function()
      combine_contexts()
    end)
  end)
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