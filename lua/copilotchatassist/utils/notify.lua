-- Utilidades para gestionar notificaciones
-- Permite un manejo centralizado de notificaciones con configuración global

local M = {}
local options = require("copilotchatassist.options")
local log = require("copilotchatassist.utils.log")

-- Muestra una notificación si está permitido según la configuración
-- @param message string: Mensaje a mostrar
-- @param level number: Nivel de log (vim.log.levels.*)
-- @param opts table: Opciones adicionales (timeout, etc.)
-- @param force boolean: Si es true, muestra la notificación incluso en modo silencioso
function M.notify(message, level, opts, force)
  -- Obtener configuración actual
  local config = options.get()

  -- Guardar en log siempre
  if level == vim.log.levels.ERROR then
    log.error(message)
  elseif level == vim.log.levels.WARN then
    log.warn(message)
  elseif level <= vim.log.levels.INFO then
    log.info(message)
  else
    log.debug(message)
  end

  -- Si estamos en modo silencioso y no es forzado, no mostrar notificaciones informativas
  if config.silent_mode and not force and level <= vim.log.levels.INFO then
    return nil
  end

  -- Preparar opciones
  opts = opts or {}
  if not opts.timeout and level <= vim.log.levels.INFO then
    opts.timeout = config.notification_timeout
  end

  -- Mostrar notificación
  return vim.notify(message, level, opts)
end

-- Notificación de éxito/completado - solo muestra notificación si es de actualización de PR
function M.success(message, opts, force)
  local config = options.get()
  local level = config.success_notification_level

  -- Siempre registrar en log
  log.info(message)

  -- Solo notificación visual para actualizaciones de PR
  local is_pr_update_notification = (
    message:match("PR.*updated") or
    message:match("PR.*complete") or
    message:match("PR.*created") or
    message:match("PR.*enhancement") or
    message:match("PR.*translation") or
    message:match("descripción.*PR.*traducida") or
    message:match("descripción.*PR.*actualizada") or
    force
  )

  if not is_pr_update_notification then
    return nil
  end

  -- Preparar opciones
  opts = opts or {}
  if not opts.timeout then
    opts.timeout = config.notification_timeout
  end

  -- Mostrar notificación con estilo de éxito
  return vim.notify(message, level, opts)
end

-- Notificación de error - solo notificación visual para errores de PR
function M.error(message, opts)
  -- Registrar siempre en el log
  log.error(message)

  -- Solo notificación visual para errores relacionados con PR
  local is_pr_error = (
    message:match("[eE]rror.*PR") or
    message:match("PR.*[eE]rror") or
    message:match("[fF]ailed.*PR") or
    message:match("PR.*[fF]ailed") or
    message:match("[eE]rror.*descripción") or
    (opts and opts.force)
  )

  if not is_pr_error then
    return nil
  end

  -- Los errores de PR sí se muestran como notificaciones
  return vim.notify(message, vim.log.levels.ERROR, opts)
end

-- Notificación de advertencia - solo notificación visual para advertencias de PR
function M.warn(message, opts)
  -- Registrar siempre en el log
  log.warn(message)

  -- Solo notificación visual para advertencias relacionadas con PR
  local is_pr_warning = (
    message:match("PR.*[wW]arn") or
    message:match("[wW]arn.*PR") or
    message:match("PR.*[rR]eintentando") or
    message:match("[aA]ctualizando.*PR") or
    (opts and opts.force)
  )

  if not is_pr_warning then
    return nil
  end

  -- Las advertencias de PR sí se muestran como notificaciones
  return vim.notify(message, vim.log.levels.WARN, opts)
end

-- Notificación informativa (nivel INFO) - solo a log excepto actualización de PR
function M.info(message, opts)
  local config = options.get()

  -- Siempre registrar en log
  log.info(message)

  -- Solo mostrar notificaciones visibles si están relacionadas con actualización de PR
  local is_pr_update_notification = (
    message:match("PR.*updated") or
    message:match("PR.*complete") or
    message:match("PR.*created") or
    message:match("PR.*enhancement") or
    message:match("PR.*translation") or
    message:match("Error.*PR") or
    message:match("actualizando PR") or
    message:match("descripción.*PR.*traducida") or
    message:match("descripción.*PR.*actualizada") or
    (opts and opts.force)
  )

  -- Para todas las demás, solo registramos en el log pero no mostramos notificación visual
  if not is_pr_update_notification then
    return nil
  end

  return vim.notify(message, config.notification_level, opts)
end

-- Notificación de depuración (solo a log)
function M.debug(message, opts)
  -- Siempre registrar en log
  log.debug(message)

  -- Nunca mostrar notificaciones visuales para debug
  return nil
end

-- Actualizar una notificación existente
function M.update(id, message, level, opts)
  if not id then return nil end

  opts = opts or {}
  opts.replace = id

  return vim.notify(message, level, opts)
end

-- Limpia todas las notificaciones existentes
function M.clear()
  -- Verificamos si nvim-notify está cargado
  local has_nvim_notify = package.loaded["notify"] ~= nil

  if has_nvim_notify then
    -- Para nvim-notify
    pcall(function()
      require("notify").dismiss()
    end)
  end

  -- Intento de limpiar notificaciones estándar de vim
  pcall(function()
    vim.cmd('echo ""')
    vim.cmd('redraw')
  end)

  log.debug("Limpiando notificaciones existentes")
end

return M