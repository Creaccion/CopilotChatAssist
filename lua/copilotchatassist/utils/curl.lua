-- Módulo de utilidades para peticiones HTTP con curl
-- Utilizado por la integración con Jira para realizar peticiones a la API

local M = {}
local log = require("copilotchatassist.utils.log")

-- Verificar si curl está disponible
local function check_curl_available()
  local curl_check = vim.fn.system("command -v curl >/dev/null 2>&1 && echo 'available' || echo 'not available'")
  return vim.trim(curl_check) == "available"
end

-- Escapar argumentos para shell
local function shell_escape(str)
  if not str then return "" end
  return vim.fn.shellescape(str)
end

-- Realizar petición HTTP usando curl
function M.request(opts, callback)
  if not check_curl_available() then
    log.error("curl no está disponible en el sistema")
    if callback then
      callback({
        status = -1,
        body = "curl no está disponible",
        headers = {}
      })
    end
    return
  end

  opts = opts or {}
  local method = opts.method or "GET"
  local url = opts.url
  local headers = opts.headers or {}
  local body = opts.body
  local timeout = opts.timeout or 10000 -- milisegundos

  if not url then
    log.error("URL no especificada para petición HTTP")
    if callback then
      callback({
        status = -1,
        body = "URL no especificada",
        headers = {}
      })
    end
    return
  end

  -- Construir comando curl
  local cmd = {
    "curl",
    "--silent",
    "--show-error",
    "-X", method,
    "-w", "\\n%{http_code}",
    "--max-time", tostring(timeout / 1000)
  }

  -- Añadir cabeceras
  for name, value in pairs(headers) do
    table.insert(cmd, "-H")
    table.insert(cmd, shell_escape(name .. ": " .. value))
  end

  -- Añadir cuerpo de la petición si es necesario
  if body and (method == "POST" or method == "PUT" or method == "PATCH") then
    table.insert(cmd, "-d")
    table.insert(cmd, shell_escape(body))
  end

  -- Añadir URL
  table.insert(cmd, shell_escape(url))

  log.debug("Ejecutando petición curl: " .. table.concat(cmd, " "))

  -- Ejecutar comando
  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if not data or #data < 2 then
        if callback then
          callback({
            status = -1,
            body = "No se recibieron datos",
            headers = {}
          })
        end
        return
      end

      -- El último elemento contiene el código de estado
      local status_code = tonumber(data[#data])
      table.remove(data, #data)

      -- Eliminar elementos vacíos al final
      while #data > 0 and data[#data] == "" do
        table.remove(data, #data)
      end

      -- El resto es el cuerpo de la respuesta
      local response_body = table.concat(data, "\n")

      if callback then
        callback({
          status = status_code,
          body = response_body,
          headers = {} -- En una implementación real, parseariamos las cabeceras de respuesta
        })
      end
    end,
    on_stderr = function(_, data, _)
      if not data or #data == 1 and data[1] == "" then return end

      local error_message = table.concat(data, "\n")
      log.error("Error en petición curl: " .. error_message)

      if callback then
        callback({
          status = -1,
          body = error_message,
          headers = {}
        })
      end
    end,
    stdout_buffered = true,
    stderr_buffered = true
  })

  if job_id <= 0 then
    log.error("No se pudo iniciar el proceso curl")
    if callback then
      callback({
        status = -1,
        body = "No se pudo iniciar el proceso curl",
        headers = {}
      })
    end
  end

  return job_id
end

-- Realizar petición GET simplificada
function M.get(url, headers, callback)
  return M.request({
    method = "GET",
    url = url,
    headers = headers
  }, callback)
end

-- Realizar petición POST simplificada
function M.post(url, body, headers, callback)
  return M.request({
    method = "POST",
    url = url,
    body = body,
    headers = headers
  }, callback)
end

-- Realizar petición PUT simplificada
function M.put(url, body, headers, callback)
  return M.request({
    method = "PUT",
    url = url,
    body = body,
    headers = headers
  }, callback)
end

-- Realizar petición DELETE simplificada
function M.delete(url, headers, callback)
  return M.request({
    method = "DELETE",
    url = url,
    headers = headers
  }, callback)
end

return M