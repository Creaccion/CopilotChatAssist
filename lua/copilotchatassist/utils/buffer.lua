-- Utility module for buffer and window operations

local M = {}

-- Create a new split and open a buffer
function M.open_split_buffer(name, content, orientation)
  -- Default to vertical split if not specified
  orientation = orientation or "vertical"

  if orientation == "vertical" then
    vim.cmd("vsplit")
  else
    vim.cmd("split")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
  vim.api.nvim_set_current_buf(buf)
  return buf
end

-- Create an editable preview buffer with callbacks
function M.create_preview_buffer(title, content, on_save_callback, on_cancel_callback)
  local log = require("copilotchatassist.utils.log")
  log.debug("create_preview_buffer invocado con título: " .. (title or "Preview"))
  log.debug("Detalles de la llamada: content_length=" .. (content and #content or 0) ..
           ", on_save_callback=" .. tostring(on_save_callback ~= nil) ..
           ", on_cancel_callback=" .. tostring(on_cancel_callback ~= nil))
  log.debug("Stack de llamada: " .. debug.traceback())

  -- Verificar título y contenido
  if not title or title == "" then
    log.warn("Título no proporcionado o vacío, usando valor predeterminado")
    title = "Preview"
  end

  if not content then
    log.warn("Contenido no proporcionado, usando valor predeterminado")
    content = "[No content provided]"
  elseif type(content) ~= "string" then
    log.error("Error: contenido debe ser un string, recibido: " .. type(content))
    return nil, nil
  end

  -- Verificar que no estamos en un modo headless
  if vim.g.headless == true then
    log.error("Error: Intentando crear buffer UI en modo headless")
    error("No se puede crear UI en modo headless")
    return nil, nil
  end

  -- Verificar si podemos usar API de UI
  local has_ui_capabilities = true
  if vim.fn.has('nvim-0.5') == 0 then
    has_ui_capabilities = false
    log.error("Error: Versión de Neovim no soportada para UI flotante")
  end

  -- Verificar si estamos en un contexto async
  if vim.in_fast_event and vim.in_fast_event() then
    log.error("Error: Intentando crear UI en un evento asíncrono")
    has_ui_capabilities = false
  end

  if not has_ui_capabilities then
    log.error("Neovim no tiene capacidades UI requeridas")
    error("Neovim no tiene capacidades UI requeridas")
    return nil, nil
  end

  -- Verificar que estamos en un entorno con capacidades de UI
  log.debug("Verificando capacidades de UI:")
  log.debug("- vim.fn.has('nvim'): " .. vim.fn.has('nvim'))
  log.debug("- vim.fn.has('terminal'): " .. vim.fn.has('terminal'))
  log.debug("- vim.fn.has('gui_running'): " .. vim.fn.has('gui_running'))

  -- Create floating window for better user experience
  local width = math.min(120, vim.o.columns - 4)
  local height = math.min(30, vim.o.lines - 4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  log.debug("Dimensiones de pantalla: columns=" .. vim.o.columns .. ", lines=" .. vim.o.lines)
  log.debug("Dimensiones de ventana flotante: " .. width .. "x" .. height ..
            " en posición " .. row .. "," .. col)

  -- Create buffer con pcall para mejor manejo de errores
  local buf = nil
  local create_buf_success, create_buf_result = pcall(function()
    return vim.api.nvim_create_buf(false, true)
  end)

  if not create_buf_success then
    log.error("Error al crear buffer: " .. tostring(create_buf_result))
    error("Error al crear buffer: " .. tostring(create_buf_result))
    return nil, nil
  end

  buf = create_buf_result

  -- Extra validation and protection
  if not buf or buf <= 0 then
    log.error("Failed to create buffer (ID inválido): " .. tostring(buf))
    error("Failed to create buffer (ID inválido)")
    return nil, nil
  end

  -- Verificar que el buffer sea válido
  local is_valid = pcall(vim.api.nvim_buf_is_valid, buf)
  if not is_valid then
    log.error("Buffer creado no es válido: " .. tostring(buf))
    error("Buffer creado no es válido")
    return nil, nil
  end

  log.debug("Buffer created successfully with ID: " .. buf)

  -- Set buffer name
  pcall(vim.api.nvim_buf_set_name, buf, title or "Preview")

  -- Set content safely
  if content and type(content) == "string" then
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, vim.split(content, "\n"))
  else
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, {"[No content]"})
  end

  -- Verificar el entorno antes de crear la ventana
  log.debug("Verificación del entorno de Neovim para UI")
  log.debug("nvim_open_win disponible: " .. tostring(vim.api.nvim_open_win ~= nil))
  log.debug("¿API UI disponible?: " .. tostring(vim.fn.has('nvim') == 1))

  -- Create window con más información de debugging
  local win_id = nil
  local win_err = nil
  log.debug("Attempting to create floating window")

  -- Usar método seguro con más logs
  local win_config = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title or "Preview",
    title_pos = "center"
  }

  log.debug("Configuración de ventana: " .. vim.inspect(win_config))

  local success, result = pcall(function()
    return vim.api.nvim_open_win(buf, true, win_config)
  end)

  -- Handle error con más detalles de debugging
  if not success then
    local error_msg = tostring(result)
    log.error("Failed to create window: " .. error_msg)

    -- Intentar diagnosticar el problema con más detalle
    log.error("Diagnóstico de error en nvim_open_win:")
    log.error("- Tipo de error: " .. type(result))
    log.error("- Mensaje: " .. tostring(result))

    if debug.traceback then
      log.error("- Stack trace: " .. debug.traceback())
    end

    -- Verificar el entorno de Neovim con más detalle
    log.error("- Versión Neovim: " .. vim.version().major .. "." ..
                                     vim.version().minor .. "." ..
                                     vim.version().patch)

    -- Verificar estado de ejecución
    log.error("- Modo de ejecución: " .. (vim.in_fast_event and vim.in_fast_event() and "async" or "sync"))
    log.error("- API UI disponible: " .. tostring(vim.api.nvim_open_win ~= nil))

    -- Verificar si hay restricciones de UI
    local ui_restrictions = {}
    if vim.g.started_by_firenvim == true then
      table.insert(ui_restrictions, "firenvim")
    end
    if vim.g.vscode then
      table.insert(ui_restrictions, "vscode")
    end
    if #ui_restrictions > 0 then
      log.error("- Restricciones de UI detectadas: " .. table.concat(ui_restrictions, ", "))
    end

    -- Intentar un método alternativo sin ventana flotante como último recurso
    log.warn("Intentando método alternativo sin ventana flotante")
    local alt_success, alt_result = pcall(function()
      -- Crear un buffer normal en lugar de flotante (con más protección)
      local cmd_success, cmd_err = pcall(function()
        vim.cmd("new")
      end)

      if not cmd_success then
        log.error("Error al crear ventana normal: " .. tostring(cmd_err))
        error("Error al crear ventana normal: " .. tostring(cmd_err))
        return nil, nil
      end

      local simple_win, simple_buf
      local win_success, win_err = pcall(function()
        simple_win = vim.api.nvim_get_current_win()
        simple_buf = vim.api.nvim_get_current_buf()
      end)

      if not win_success then
        log.error("Error al obtener ventana/buffer actuales: " .. tostring(win_err))
        error("Error al obtener ventana/buffer actuales: " .. tostring(win_err))
        return nil, nil
      end

      log.debug("Método alternativo: buffer=" .. simple_buf .. ", ventana=" .. simple_win)

      -- Configurar el buffer con protección
      pcall(function()
        vim.api.nvim_buf_set_name(simple_buf, title or "Preview")
      end)

      pcall(function()
        vim.api.nvim_buf_set_lines(simple_buf, 0, -1, false, vim.split(content, "\n"))
      end)

      -- Configurar opciones
      pcall(function()
        vim.api.nvim_win_set_option(simple_win, "number", false)
      end)

      -- Verificación final
      local is_buf_valid = pcall(vim.api.nvim_buf_is_valid, simple_buf)
      local is_win_valid = pcall(vim.api.nvim_win_is_valid, simple_win)

      if not (is_buf_valid and is_win_valid) then
        log.error("Ventana o buffer alternativo no válidos")
        error("Ventana o buffer alternativo no válidos")
        return nil, nil
      end

      log.debug("Método alternativo creado con éxito")
      return simple_buf, simple_win
    end)

    if alt_success then
      log.info("Método alternativo sin ventana flotante implementado correctamente")
      local alt_buf, alt_win = unpack(alt_result)
      return alt_buf, alt_win
    else
      -- Si todos los métodos fallan, lanzar error
      error("Failed to create any type of window: " .. error_msg)
      return buf, nil
    end
  else
    win_id = result
    log.debug("Window created successfully with ID: " .. win_id)

    -- Verificar que la ventana se creó correctamente
    if not vim.api.nvim_win_is_valid(win_id) then
      log.error("Window created but not valid!")
      error("Window created but not valid")
      return buf, nil
    end
  end

  -- Set local mappings for save and cancel
  pcall(function()
    vim.api.nvim_buf_set_keymap(buf, "n", "<leader>s", "", {
      callback = function()
        local buffer_content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local content_str = table.concat(buffer_content, "\n")

        -- Close buffer and window
        pcall(vim.api.nvim_win_close, win_id, true)

        -- Call save callback with content
        if on_save_callback then
          on_save_callback(content_str)
        end
      end,
      noremap = true,
      desc = "Save changes and update PR"
    })
  end)

  pcall(function()
    vim.api.nvim_buf_set_keymap(buf, "n", "<leader>q", "", {
      callback = function()
        -- Close buffer and window
        pcall(vim.api.nvim_win_close, win_id, true)

        -- Call cancel callback
        if on_cancel_callback then
          on_cancel_callback()
        end
      end,
      noremap = true,
      desc = "Cancel and discard changes"
    })
  end)

  -- Add instructions at the bottom
  vim.api.nvim_win_set_option(win_id, "winhighlight", "NormalFloat:Normal")

  -- Set buffer as modifiable
  pcall(function()
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_option(buf, "buftype", "")
    log.debug("Buffer options set: modifiable=true, buftype=''")
  end)

  -- Create auto commands for window con verificación adicional
  local augroup_success, augroup_err = pcall(function()
    local augroup = vim.api.nvim_create_augroup("PreviewBuffer", { clear = true })
    vim.api.nvim_create_autocmd("BufWinLeave", {
      group = augroup,
      buffer = buf,
      callback = function()
        log.debug("Evento BufWinLeave detectado, invocando callback de cancelación")
        if on_cancel_callback then
          on_cancel_callback()
        end
      end
    })
    log.debug("Autocomandos configurados correctamente para buffer " .. buf)
    return true
  end)

  if not augroup_success then
    log.error("Error al configurar autocomandos: " .. tostring(augroup_err))
  end

  -- Show instructions con verificación adicional
  vim.defer_fn(function()
    local echo_success, echo_err = pcall(function()
      vim.api.nvim_echo({{
        "Edit PR content | <leader>s to save and update | <leader>q to cancel",
        "MoreMsg"
      }}, false, {})
      log.debug("Instructions displayed to user")
    end)

    if not echo_success then
      log.error("Error al mostrar instrucciones: " .. tostring(echo_err))
    end

    -- Verificación adicional de que el buffer sigue siendo válido
    local is_still_valid = pcall(vim.api.nvim_buf_is_valid, buf)
    local is_focused = false
    pcall(function()
      is_focused = vim.api.nvim_get_current_buf() == buf
    end)

    log.debug("Estado del buffer después de 100ms: válido=" .. tostring(is_still_valid) ..
              ", enfocado=" .. tostring(is_focused))

    if not is_still_valid then
      log.warn("¡Advertencia! El buffer ya no es válido después de 100ms")
    end

    if not is_focused then
      log.warn("¡Advertencia! El buffer no está enfocado después de 100ms")
    end
  end, 100)

  log.debug("Preview buffer setup complete. Buffer: " .. buf .. ", Window: " .. win_id)

  -- Verificación final de validez
  local final_buf_valid = pcall(vim.api.nvim_buf_is_valid, buf)
  local final_win_valid = pcall(vim.api.nvim_win_is_valid, win_id)

  if not final_buf_valid then
    log.error("¡ERROR CRÍTICO! El buffer no es válido justo antes de retornar")
  end

  if not final_win_valid then
    log.error("¡ERROR CRÍTICO! La ventana no es válida justo antes de retornar")
  end

  -- Verificar que el buffer está asociado a la ventana
  local win_buf = -1
  pcall(function()
    win_buf = vim.api.nvim_win_get_buf(win_id)
  end)

  if win_buf ~= buf then
    log.warn("¡Advertencia! El buffer (" .. buf .. ") no está asociado a la ventana (buffer actual: " .. win_buf .. ")")
  end

  -- Registrar una verificación adicional para detectar cierre prematuro
  vim.defer_fn(function()
    local still_valid_buf = pcall(vim.api.nvim_buf_is_valid, buf)
    local still_valid_win = pcall(vim.api.nvim_win_is_valid, win_id)

    log.debug("Estado después de 200ms: buffer válido=" .. tostring(still_valid_buf) ..
              ", ventana válida=" .. tostring(still_valid_win))
  end, 200)

  return buf, win_id
end

-- Create a dual preview buffer for both title and description
function M.create_pr_preview(title, description, on_save_callback, on_cancel_callback)
  -- Create a combined content with separator
  local combined_content = "# PR Title\n" .. title .. "\n\n" ..
                          "# PR Description\n" .. description

  -- Create preview buffer
  local buf, win_id = M.create_preview_buffer("PR Preview", combined_content, function(content)
    -- Extract title and description from combined content
    local lines = vim.split(content, "\n")
    local new_title = ""
    local new_description = ""
    local in_title = false
    local in_description = false

    for i, line in ipairs(lines) do
      if line == "# PR Title" then
        in_title = true
        in_description = false
      elseif line == "# PR Description" then
        in_title = false
        in_description = true
      elseif in_title then
        if new_title == "" then
          new_title = line
        end
      elseif in_description then
        if new_description == "" then
          new_description = line
        else
          new_description = new_description .. "\n" .. line
        end
      end
    end

    -- Call save callback with extracted title and description
    if on_save_callback then
      on_save_callback(new_title, new_description)
    end
  end, on_cancel_callback)

  return buf, win_id
end

return M
