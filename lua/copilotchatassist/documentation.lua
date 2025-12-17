-- Módulo consolidado de documentación para CopilotChatAssist
-- Integra las funcionalidades de doc_review.lua, doc_changes.lua y documentation/init.lua

local M = {}
local log = require("copilotchatassist.utils.log")
local i18n = require("copilotchatassist.i18n")

-- Declaraciones de módulos que se cargarán perezosamente
local detector, generator, updater, fullfile_documenter, git_changes, preview_panel

-- Lista de archivos Markdown recomendados para cualquier proyecto
local recommended_markdown = {
  "README.md",
  "CHANGELOG.md",
  "CONTRIBUTING.md",
  "CODE_OF_CONDUCT.md",
  "LICENSE.md"
}

-- Función para cargar módulos bajo demanda
local function load_modules()
  if not detector then
    detector = require("copilotchatassist.documentation.detector")
  end

  if not generator then
    generator = require("copilotchatassist.documentation.generator")
  end

  if not updater then
    updater = require("copilotchatassist.documentation.updater")
  end

  if not fullfile_documenter then
    fullfile_documenter = require("copilotchatassist.documentation.fullfile_documenter")
  end

  if not git_changes then
    git_changes = require("copilotchatassist.documentation.git_changes")
  end

  if not preview_panel then
    preview_panel = require("copilotchatassist.documentation.preview_panel")
  end

  return detector, generator, updater, fullfile_documenter, git_changes, preview_panel
end

-- Estado del módulo
M.state = {
  last_scan = nil,          -- Timestamp del último escaneo
  detected_items = {},      -- Elementos detectados para documentación
  current_buffer = nil,     -- Buffer actual siendo procesado
  processing = false,       -- Indicador de procesamiento en curso
  preview_mode = false      -- Modo de previsualización activo
}

-- Opciones configurables
M.options = {
  auto_detect = false,      -- Detectar automáticamente al guardar archivos
  style_match = true,       -- Intentar hacer coincidir el estilo de documentación existente
  generate_params = true,   -- Generar documentación para parámetros
  generate_returns = true,  -- Generar documentación para valores de retorno
  include_examples = false, -- Incluir ejemplos en la documentación generada
  min_context_lines = 10,   -- Líneas de contexto mínimas a considerar
  use_fullfile_approach = true, -- Usar el enfoque de documentación de archivo completo
}

-- Lenguajes soportados actualmente
M.supported_languages = {
  lua = true,
  python = true,
  javascript = true,
  typescript = true,
  java = true,
  elixir = true,
  ruby = true,
  sh = true,        -- Bash
  bash = true,      -- Bash alternativo
  terraform = true, -- HCL para Terraform
  hcl = true,       -- HCL genérico
  yaml = true,      -- Para Kubernetes
  dockerfile = true -- Para Dockerfiles
}

-- Configuración inicial del módulo
function M.setup(opts)
  if opts then
    for k, v in pairs(opts) do
      if M.options[k] ~= nil then
        M.options[k] = v
      end
    end
  end

  -- Configurar autocomandos si se habilita la detección automática
  if M.options.auto_detect then
    M._setup_autocommands()
  end

  log.debug("Módulo de documentación inicializado")
end

-- Configura los autocomandos para la detección automática
function M._setup_autocommands()
  local group = vim.api.nvim_create_augroup("CopilotDocAssistAuto", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = {"*.lua", "*.py", "*.js", "*.ts", "*.jsx", "*.tsx"},
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if M.supported_languages[ft] then
        M.scan_buffer(ev.buf, { auto_mode = true })
      end
    end,
    desc = "CopilotChatAssist: Detectar documentación desactualizada al guardar"
  })
end

-- Devuelve una tabla de archivos Markdown recomendados faltantes en la raíz del proyecto
function M.get_missing_markdown_files(project_root)
  local missing = {}
  for _, filename in ipairs(recommended_markdown) do
    local path = project_root .. "/" .. filename
    local file = io.open(path, "r")
    if not file then
      table.insert(missing, filename)
    else
      file:close()
    end
  end
  return missing
end

-- Genera un prompt de documentación según el tipo de archivo
function M.generate_doc_prompt(filetype, filepath)
  local prompts = {
    lua = "Generate LuaDoc-style documentation for all public functions and modules in this file.",
    python = "Generate docstrings for all public classes and functions using Google style.",
    ruby = "Generate YARD documentation for all public methods and classes.",
    elixir = "Generate module and function documentation using Elixir's @moduledoc and @doc.",
    terraform = "Add comments explaining each resource and variable in Terraform format.",
    yaml = "Document each Kubernetes manifest with comments describing its purpose.",
    java = "Generate JavaDoc comments for all public classes and methods.",
    markdown = "Review and improve the Markdown documentation for clarity and completeness."
  }
  return prompts[filetype] or "Generate appropriate documentation for this file type."
end

-- Función principal para sugerir cambios de documentación y archivos Markdown faltantes
function M.suggest_doc_changes(filetype, filepath, project_root)
  local doc_prompt = M.generate_doc_prompt(filetype, filepath)
  local missing_md = M.get_missing_markdown_files(project_root)
  local suggestion = doc_prompt
  if #missing_md > 0 then
    suggestion = suggestion .. "\n\nRecommended Markdown files missing: " .. table.concat(missing_md, ", ") .. ". Propose their creation with best-practice content."
  end
  return suggestion
end

-- Retorna un prompt para revisar y sugerir actualizaciones para un archivo Markdown
function M.review_markdown_prompt(filepath)
  return string.format(
    "Review the Markdown documentation in '%s'. Suggest improvements for clarity, completeness, formatting, and alignment with project best practices. If sections are outdated or missing, propose updates or additions.",
    filepath
  )
end

-- Realizar revisión de documentación
function M.doc_review()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo.filetype

  -- Verificar si el archivo es de tipo Markdown
  if filetype == "markdown" then
    local prompt = M.review_markdown_prompt(filepath)
    require("copilotchatassist.copilotchat_api").ask(prompt)
  else
    local project_root = vim.fn.getcwd()
    local suggestion = M.suggest_doc_changes(filetype, filepath, project_root)
    require("copilotchatassist.copilotchat_api").ask(suggestion)
  end
end

-- Documentar cambios
function M.doc_changes()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo.filetype
  local project_root = vim.fn.getcwd()

  -- Generar sugerencias para documentar los cambios
  local suggestion = M.suggest_doc_changes(filetype, filepath, project_root)
  require("copilotchatassist.copilotchat_api").ask(suggestion)
end

-- Escanear buffer en búsqueda de elementos sin documentación
function M.scan_buffer(buffer, opts)
  opts = opts or {}
  buffer = buffer or vim.api.nvim_get_current_buf()

  -- Evitar escaneos concurrentes
  if M.state.processing then
    log.warn("Ya hay un proceso de documentación en curso")
    return false
  end

  local filetype = vim.bo[buffer].filetype
  if not M.supported_languages[filetype] then
    log.warn("Tipo de archivo no soportado para análisis de documentación: " .. filetype)
    return false
  end

  M.state.processing = true
  M.state.current_buffer = buffer
  M.state.last_scan = os.time()
  M.state.detected_items = {}
  M.state.changed_items = {}

  -- Cargar módulos bajo demanda
  local detector_module, _, _, _, git_changes_module = load_modules()
  if not detector_module then
    log.error("No se pudo cargar el módulo detector")
    M.state.processing = false
    return false
  end

  -- Obtener resultados del detector para elementos sin documentación o incompletos
  local items = detector_module.scan_buffer(buffer)

  -- Detectar elementos que han cambiado recientemente si se solicita
  if opts.detect_changes or opts.include_changes then
    log.debug("Detectando elementos modificados en git para buffer " .. buffer)
    local file_path = vim.api.nvim_buf_get_name(buffer)

    if file_path and file_path ~= "" then
      local git_opts = {
        num_commits = opts.num_commits or 5  -- Por defecto revisar los últimos 5 commits
      }

      local changed_items = git_changes_module.detect_changed_elements(buffer, git_opts)

      if changed_items and #changed_items > 0 then
        log.debug("Se encontraron " .. #changed_items .. " elementos modificados en git")

        -- Guardar los elementos modificados
        M.state.changed_items = changed_items

        -- Combinar elementos detectados y cambios de git
        items = git_changes_module.combine_with_changes(items, changed_items)

        -- Log para depuración
        log.debug("Total de elementos tras combinar: " .. #items)
      end
    else
      log.debug("No se pudo obtener la ruta del archivo para detectar cambios en git")
    end
  end

  M.state.detected_items = items

  -- En modo automático, solo notificar si se encuentran problemas
  if opts.auto_mode then
    if #items > 0 then
      vim.defer_fn(function()
        vim.notify(string.format(
          "CopilotDocAssist: Se detectaron %d elementos de documentación desactualizados. Ejecuta :CopilotDocSync para corregir.",
          #items
        ), vim.log.levels.INFO)
      end, 500)
    end
  else
    -- En modo manual, mostrar resultados
    M.show_detection_results(items)
  end

  M.state.processing = false
  return true
end

-- Show detection results to the user
function M.show_detection_results(items)
  if #items == 0 then
    vim.notify("No se encontraron problemas de documentación", vim.log.levels.INFO)
    return
  end

  -- Agrupar por tipo
  local by_type = {
    missing = {},
    outdated = {},
    incomplete = {}
  }

  for _, item in ipairs(items) do
    table.insert(by_type[item.issue_type], item)
  end

  -- Mostrar resumen
  local msg = string.format(
    "Detectados %d elementos de documentación:\n- %d sin documentación\n- %d desactualizados\n- %d incompletos",
    #items,
    #by_type.missing,
    #by_type.outdated,
    #by_type.incomplete
  )

  vim.notify(msg, vim.log.levels.INFO)
end

-- Sincroniza la documentación en un buffer (actualiza o genera)
function M.sync_doc(opts)
  opts = opts or {}
  local buffer = opts.buffer or vim.api.nvim_get_current_buf()

  -- Función para mostrar opciones avanzadas
  local function show_advanced_options()
    -- Opciones avanzadas
    vim.ui.select(
      {
        i18n.t("advanced_options.detect_git_changes"),
        i18n.t("advanced_options.document_modified"),
        i18n.t("advanced_options.document_undocumented"),
        i18n.t("advanced_options.document_git_modified"),
        i18n.t("advanced_options.preview_all_comments"),
        i18n.t("advanced_options.document_full_file"),
        i18n.t("menu.back_to_main")
      },
      { prompt = i18n.t("menu.advanced_options") .. ":" },
      function(choice)
        if choice == i18n.t("advanced_options.detect_git_changes") then
          -- Preguntar cuántos commits revisar
          vim.ui.input(
            { prompt = i18n.t("advanced_options.prompt_commits") },
            function(input)
              local num_commits = tonumber(input) or 5
              num_commits = math.min(math.max(num_commits, 1), 20)  -- Entre 1 y 20

              -- Escanear con detección de cambios en git
              M.scan_buffer(buffer, {
                detect_changes = true,
                include_records = true,
                num_commits = num_commits
              })

              if #M.state.detected_items > 0 then
                -- Continuar con la selección de acciones
                vim.ui.select(
                  {i18n.t("menu.update_all"), i18n.t("menu.select_elements"), i18n.t("menu.advanced_options")},
                  { prompt = i18n.t("documentation.elements_found", {#M.state.detected_items}) .. ". " .. i18n.t("menu.what_action") },
                  function(action_choice)
                    if action_choice == i18n.t("menu.update_all") then
                      M._process_all_items()
                    elseif action_choice == i18n.t("menu.select_elements") then
                      M._show_item_selector()
                    elseif action_choice == i18n.t("menu.advanced_options") then
                      show_advanced_options()
                    end
                  end
                )
              else
                vim.notify(i18n.t("documentation.no_elements_found"), vim.log.levels.INFO)
                show_advanced_options()
              end
            end
          )
        elseif choice == i18n.t("advanced_options.document_modified") then
          -- Escanear con detección de cambios en git
          M.scan_buffer(buffer, { detect_changes = true, include_records = true })

          -- Filtrar solo los elementos modificados
          local changed_items = {}
          for _, item in ipairs(M.state.detected_items) do
            if item.changed then
              table.insert(changed_items, item)
            end
          end

          M.state.detected_items = changed_items

          if #M.state.detected_items > 0 then
            M._show_item_selector()
          else
            vim.notify(i18n.t("documentation.no_modified_elements", {0}), vim.log.levels.INFO)
            show_advanced_options()
          end
        elseif choice == i18n.t("advanced_options.document_undocumented") then
          -- Escanear elementos sin documentación
          M.scan_buffer(buffer, { include_records = true })

          -- Filtrar solo los elementos sin documentación
          local missing_items = {}
          for _, item in ipairs(M.state.detected_items) do
            if item.issue_type == "missing" then
              table.insert(missing_items, item)
            end
          end

          M.state.detected_items = missing_items

          if #M.state.detected_items > 0 then
            M._show_item_selector()
          else
            vim.notify(i18n.t("documentation.no_elements_found"), vim.log.levels.INFO)
            show_advanced_options()
          end
        elseif choice == i18n.t("advanced_options.document_git_modified") then
          -- Preguntar cuántos commits revisar
          vim.ui.input(
            { prompt = i18n.t("advanced_options.prompt_commits") },
            function(input)
              local num_commits = tonumber(input) or 5
              num_commits = math.min(math.max(num_commits, 1), 20)  -- Entre 1 y 20

              -- Cargar módulo git_changes si no está cargado
              local detector_module, generator_module, updater_module, fullfile_documenter_module, git_changes_module = load_modules()
              if not git_changes_module then
                log.error("No se pudo cargar el módulo de detección de cambios git")
                vim.notify("Error: No se pudo cargar el módulo de detección de cambios git", vim.log.levels.ERROR)
                return
              end

              -- Obtener el path del archivo
              local file_path = vim.api.nvim_buf_get_name(buffer)
              if not file_path or file_path == "" then
                vim.notify(i18n.t("documentation.buffer_not_valid"), vim.log.levels.WARN)
                show_advanced_options()
                return
              end

              -- Ejecutar comando git para ver si el archivo es parte de un repositorio
              local cmd = string.format("git ls-files --error-unmatch %s 2>/dev/null", vim.fn.shellescape(file_path))
              local git_result = os.execute(cmd)
              if git_result ~= 0 then
                vim.notify("El archivo no está en un repositorio git o git no está disponible", vim.log.levels.WARN)
                show_advanced_options()
                return
              end

              -- Notificar al usuario que se están detectando cambios
              vim.notify(i18n.t("documentation.detected_changes", {num_commits}), vim.log.levels.INFO)

              -- Detectar cambios usando git_changes
              local git_opts = { num_commits = num_commits }
              local changed_elements = git_changes_module.detect_changed_elements(buffer, git_opts)

              if #changed_elements == 0 then
                vim.notify(i18n.t("documentation.no_modified_elements", {num_commits}), vim.log.levels.INFO)
                show_advanced_options()
                return
              end

              -- Actualizar los elementos detectados con solo los modificados
              M.state.detected_items = changed_elements
              vim.notify(i18n.t("documentation.found_modified_elements", {#changed_elements, num_commits}), vim.log.levels.INFO)

              -- Mostrar el selector de elementos
              M._show_item_selector()
            end
          )
        elseif choice == i18n.t("advanced_options.preview_all_comments") then
          -- Activar modo previsualización y mostrar todos los elementos
          M.state.preview_mode = true

          -- Detectar todos los elementos (documentados y sin documentar)
          local all_elements = detector.scan_buffer(buffer, {include_documented = true})

          -- Verificar si hay elementos modificados en git
          if not git_changes then
            git_changes = require("copilotchatassist.documentation.git_changes")
          end

          local changed_elements = git_changes.detect_changed_elements(buffer, {num_commits = 5})
          local changed_lookup = {}

          -- Crear tabla de búsqueda rápida para elementos cambiados
          for _, changed_item in ipairs(changed_elements) do
            local key = changed_item.start_line .. "_" .. changed_item.end_line
            changed_lookup[key] = true
          end

          -- Marcar elementos cambiados en la lista completa
          for _, item in ipairs(all_elements) do
            local key = item.start_line .. "_" .. item.end_line
            if changed_lookup[key] then
              item.changed = true
            end
          end

          -- Establecer la lista de elementos
          M.state.detected_items = all_elements
          M._process_all_items()
          M.state.preview_mode = false
        elseif choice == i18n.t("advanced_options.document_full_file") then
          -- Usar el enfoque de archivo completo
          M.document_full_file(buffer, opts)
        elseif choice == i18n.t("menu.back_to_main") then
          -- Volver al menú principal
          start_main_menu()
        end
      end
    )
  end

  -- Función para iniciar el menú principal
  local function start_main_menu()
    -- Verificar si debemos usar el enfoque de archivo completo por defecto
    if opts.fullfile or (M.options.use_fullfile_approach and not opts.selective) then
      return M.document_full_file(buffer, opts)
    end

    -- Verificar si es un archivo Java para detectar records
    local filetype = vim.bo[buffer].filetype
    local detect_records = filetype == "java"

    -- Si no hay detección previa o se solicita reescaneo, escanear primero
    if opts.rescan or not M.state.detected_items or #M.state.detected_items == 0 or M.state.current_buffer ~= buffer then
      -- Para archivos Java, activar la detección especializada de records
      if detect_records then
        log.debug("Activando detección especializada de records de Java")
        M.scan_buffer(buffer, {include_records = true})
      else
        M.scan_buffer(buffer)
      end
    end

    if #M.state.detected_items == 0 then
      -- Para Java, ofrecer escaneo especializado de records si aún no se ha hecho
      if detect_records and not opts.records_checked then
        log.debug("Intentando detección especializada de records de Java")

        -- Cargar módulos bajo demanda
        load_modules()
        local java_handler = require("copilotchatassist.documentation.language.java")

        -- Intentar detectar records específicamente
        local records = java_handler.detect_java_records(buffer)

        if records and #records > 0 then
          log.debug("Se encontraron " .. #records .. " records de Java específicamente")
          M.state.detected_items = records
          vim.notify("Se encontraron " .. #records .. " records de Java para documentar", vim.log.levels.INFO)
        else
          vim.notify("No se encontraron elementos para documentar. Prueba con opciones avanzadas.", vim.log.levels.INFO)
          show_advanced_options()
          return
        end
      else
        vim.notify("No se encontraron elementos para documentar. Prueba con opciones avanzadas.", vim.log.levels.INFO)
        show_advanced_options()
        return
      end
    end

    -- Confirmar acción
    vim.ui.select(
      {i18n.t("menu.update_all"), i18n.t("menu.select_elements"), i18n.t("menu.preview_changes"), i18n.t("menu.advanced_options"), i18n.t("menu.cancel")},
      { prompt = i18n.t("menu.what_action") },
      function(choice)
        if choice == i18n.t("menu.update_all") then
          M._process_all_items()
        elseif choice == i18n.t("menu.select_elements") then
          M._show_item_selector()
        elseif choice == i18n.t("menu.preview_changes") then
          M.state.preview_mode = true
          M._process_all_items()
          M.state.preview_mode = false
        elseif choice == i18n.t("menu.advanced_options") then
          show_advanced_options()
        end
      end
    )
  end

  -- Iniciar el menú principal
  start_main_menu()
end

-- Procesar todos los elementos detectados
function M._process_all_items()
  local items = M.state.detected_items
  if #items == 0 then return end

  -- Cargar módulos bajo demanda
  local detector_module, generator_module, updater_module = load_modules()
  if not generator_module or not updater_module then
    log.error("No se pudieron cargar los módulos necesarios")
    vim.notify("Error: No se pudieron cargar los módulos necesarios", vim.log.levels.ERROR)
    return
  end

  vim.notify("Procesando " .. #items .. " elementos de documentación...", vim.log.levels.INFO)

  -- Agrupar por tipo para procesamiento más eficiente
  for _, item in ipairs(items) do
    if item.issue_type == "missing" then
      generator_module.generate_documentation(item)
    elseif item.issue_type == "outdated" or item.issue_type == "incomplete" then
      updater_module.update_documentation(item)
    end
  end
end

-- Mostrar selector de elementos a procesar
function M._show_item_selector()
  local items = M.state.detected_items
  if #items == 0 then return end

  -- Crear opciones para el selector
  local options = {}
  for i, item in ipairs(items) do
    -- Determinar el estado del elemento
    local status_indicator = item.issue_type

    -- Añadir indicador si el elemento ha sido modificado
    if item.changed then
      status_indicator = status_indicator .. " 🔄"  -- Emoji para indicar cambio
    end

    -- Formato del label para mostrar más información
    local label = string.format(
      "[%s] %s (%s:%d)",
      status_indicator,
      item.name,
      vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.bufnr), ":t"),
      item.start_line
    )
    table.insert(options, { label = label, item = item, index = i })
  end

  -- Añadir opción para filtrar solo elementos modificados
  table.insert(options, 1, { label = "--- [FILTRO] Mostrar solo elementos modificados ---", is_filter = true, filter = "changed" })
  -- Añadir opción para filtrar solo elementos sin documentación
  table.insert(options, 2, { label = "--- [FILTRO] Mostrar solo elementos sin documentación ---", is_filter = true, filter = "missing" })
  -- Añadir opción para mostrar todos los elementos
  table.insert(options, 3, { label = "--- [FILTRO] Mostrar todos los elementos ---", is_filter = true, filter = "all" })

  -- Cargar módulos bajo demanda
  local detector_module, generator_module, updater_module = load_modules()
  if not generator_module or not updater_module then
    log.error("No se pudieron cargar los módulos necesarios")
    vim.notify("Error: No se pudieron cargar los módulos necesarios", vim.log.levels.ERROR)
    return
  end

  -- Variable para almacenar el filtro actual
  local current_filter = "all"

  -- Función para filtrar los elementos
  local function apply_filter(filter_type)
    local filtered_options = {}

    -- Añadir siempre las opciones de filtro
    table.insert(filtered_options, options[1]) -- Filtro de cambios
    table.insert(filtered_options, options[2]) -- Filtro de sin documentación
    table.insert(filtered_options, options[3]) -- Filtro de todos

    -- Aplicar el filtro seleccionado
    for i = 4, #options do
      local opt = options[i]
      if filter_type == "all" or
         (filter_type == "changed" and opt.item.changed) or
         (filter_type == "missing" and opt.item.issue_type == "missing") then
        table.insert(filtered_options, opt)
      end
    end

    return filtered_options
  end

  -- Función recursiva para mostrar el selector con filtros
  local function show_selector(filter_type)
    local filtered_options = apply_filter(filter_type)

    vim.ui.select(
      filtered_options,
      {
        prompt = "Selecciona un elemento para documentar (filtro: " .. filter_type .. ")",
        format_item = function(opt) return opt.label end
      },
      function(choice)
        if not choice then return end

        -- Si es una opción de filtro, cambiar el filtro y mostrar de nuevo
        if choice.is_filter then
          show_selector(choice.filter)
          return
        end

        -- Procesar elemento seleccionado
        local item = choice.item
        if item.issue_type == "missing" then
          generator_module.generate_documentation(item)
        else
          updater_module.update_documentation(item)
        end

        -- Mostrar el selector de nuevo para permitir múltiples selecciones
        show_selector(filter_type)
      end
    )
  end

  -- Iniciar el selector con el filtro "all"
  show_selector("all")
end

-- Documentar un archivo completo usando el enfoque de CopilotChat
function M.document_full_file(buffer, opts)
  opts = opts or {}
  buffer = buffer or vim.api.nvim_get_current_buf()

  -- Cargar el módulo de documentación de archivo completo
  if not fullfile_documenter then
    fullfile_documenter = require("copilotchatassist.documentation.fullfile_documenter")
  end

  -- Verificar si el tipo de archivo es soportado
  local filetype = vim.bo[buffer].filetype
  if not M.supported_languages[filetype] then
    vim.notify("Tipo de archivo no soportado para documentación: " .. filetype, vim.log.levels.WARN)
    return false
  end

  -- Obtener la ruta del archivo si está disponible
  local file_path = vim.api.nvim_buf_get_name(buffer)
  local is_file = file_path and file_path ~= ""

  -- Determinar si vamos a usar el método de buffer o de archivo
  if is_file then
    -- Preguntar al usuario qué prefiere hacer
    vim.ui.select(
      {"Actualizar buffer y archivo", "Solo previsualizar cambios", "Solo actualizar buffer", "Cancelar"},
      { prompt = "¿Cómo desea documentar el archivo?" },
      function(choice)
        if not choice or choice == "Cancelar" then
          return
        end

        local doc_opts = vim.deepcopy(opts)

        if choice == "Solo previsualizar cambios" then
          doc_opts.preview_only = true
          fullfile_documenter.document_buffer(buffer, doc_opts)
        elseif choice == "Solo actualizar buffer" then
          doc_opts.no_save = true
          fullfile_documenter.document_buffer(buffer, doc_opts)
        else -- Actualizar buffer y archivo
          doc_opts.save = true

          -- Añadir información de depuración adicional antes de llamar a document_buffer
          local debug_dir = vim.fn.stdpath("cache") .. "/copilotchatassist"
          vim.fn.mkdir(debug_dir, "p")
          local debug_file = debug_dir .. "/document_call_debug.txt"
          local debug_f = io.open(debug_file, "w")
          if debug_f then
            debug_f:write("Llamando a document_buffer con buffer: " .. buffer .. "\n")
            debug_f:write("Ruta del archivo: " .. vim.api.nvim_buf_get_name(buffer) .. "\n")
            debug_f:write("Opciones: save=" .. tostring(doc_opts.save) .. "\n")
            debug_f:close()
          end

          fullfile_documenter.document_buffer(buffer, doc_opts)
        end
      end
    )
    return true
  else
    -- Es un buffer sin archivo, documentar directamente
    local success, result = fullfile_documenter.document_buffer(buffer, opts)
    return success
  end
end

-- Generar documentación para una función/clase/record específica en la posición del cursor
function M.generate_doc_at_cursor(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype

  -- Verificar si debemos usar el enfoque de archivo completo
  if M.options.use_fullfile_approach then
    return M.document_full_file(bufnr, opts)
  end

  if not M.supported_languages[filetype] then
    vim.notify("Tipo de archivo no soportado: " .. filetype, vim.log.levels.WARN)
    return
  end

  -- Cargar módulos bajo demanda
  local detector_module, generator_module, updater_module = load_modules()
  if not detector_module or not generator_module or not updater_module then
    log.error("No se pudieron cargar los módulos necesarios")
    vim.notify("Error: No se pudieron cargar los módulos necesarios", vim.log.levels.ERROR)
    return
  end

  -- Obtener posición del cursor
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  -- Para archivos Java, verificar si es un record
  local item = nil

  if filetype == "java" then
    -- Intentar detectar si hay un record en la posición actual
    local java_handler = require("copilotchatassist.documentation.language.java")
    local content = vim.api.nvim_buf_get_lines(bufnr, row-1, row, false)[1] or ""

    -- Si la línea actual contiene la palabra "record", probablemente sea un record
    if content:match("record%s+") or content:match("public%s+record%s+") then
      log.debug("Posible record de Java detectado en la línea del cursor")

      -- Intentar detectar records en todo el buffer
      local records = java_handler.detect_java_records(bufnr)

      -- Encontrar el record más cercano a la posición actual
      if records and #records > 0 then
        local closest_record = nil
        local min_distance = math.huge

        for _, record in ipairs(records) do
          local distance = math.abs(record.start_line - row)
          if distance < min_distance then
            min_distance = distance
            closest_record = record
          end
        end

        if closest_record and min_distance <= 5 then
          log.debug("Record encontrado cerca de la posición del cursor: " .. closest_record.name)
          item = closest_record
        end
      end
    end
  end

  -- Si no se detectó un record (o no es Java), usar la detección estándar
  if not item then
    item = detector_module.detect_at_position(bufnr, row)
  end

  if not item then
    vim.notify("No se detectó ninguna función, clase o record en la posición actual", vim.log.levels.WARN)
    return
  end

  -- Mostrar mensaje informativo
  vim.notify("Generando documentación para " ..
             (item.type or "elemento") ..
             ": " .. item.name, vim.log.levels.INFO)

  -- Procesar según el tipo de problema
  if item.issue_type == "missing" then
    generator_module.generate_documentation(item)
  else
    updater_module.update_documentation(item)
  end
end

return M