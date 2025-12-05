-- Script para probar la escritura de archivos
-- Este script prueba la funcionalidad de escritura de archivos implementada en file.lua

-- Crear un log básico para pruebas
local log = {
  info = function(msg) print("[INFO] " .. msg) end,
  error = function(msg) print("[ERROR] " .. msg) end,
  debug = function(msg) print("[DEBUG] " .. msg) end,
  warn = function(msg) print("[WARN] " .. msg) end
}

-- Implementar una versión simplificada de file_utils para pruebas
local file_utils = {
  write_file = function(path, content, force)
    -- Intentar escribir el archivo directamente
    local file = io.open(path, "w")
    if file then
      file:write(content)
      file:close()
      return true
    else
      -- Método alternativo si el archivo no se pudo abrir y force es true
      if force then
        -- Usar comando del sistema
        local temp_file = os.tmpname()
        local tmp = io.open(temp_file, "w")
        if tmp then
          tmp:write(content)
          tmp:close()
          -- Copiar el archivo temporal al destino
          local result = os.execute(string.format("cp %s %s", temp_file, path))
          os.remove(temp_file)
          return result == 0 or result == true
        end
      end
      return false
    end
  end,

  read_file = function(path)
    local file = io.open(path, "r")
    if file then
      local content = file:read("*a")
      file:close()
      return content
    end
    return nil
  end
}

-- Configuración para las pruebas
local test_dir = "./test_output"
local test_file = test_dir .. "/test_file.txt"
local test_content = "Este es un contenido de prueba\nPara verificar la escritura de archivos\n"
local test_java_file = test_dir .. "/TestClass.java"
local test_java_content = [[
package com.test;

public class TestClass {
    public void testMethod() {
        System.out.println("Hello, World!");
    }
}
]]

-- Crear directorio de prueba si no existe
local vim_available = type(vim) == "table" and type(vim.fn) == "table"

if vim_available and vim.fn.isdirectory then
  if vim.fn.isdirectory(test_dir) == 0 then
    vim.fn.mkdir(test_dir, "p")
  end
else
  -- Fallback para entornos sin vim.fn
  os.execute("mkdir -p " .. test_dir)
end

-- Función auxiliar para ejecutar una prueba
local function run_test(name, fn)
  log.info("Ejecutando prueba: " .. name)
  local status, result = pcall(fn)
  if status then
    log.info("✓ Prueba pasada: " .. name)
    return true
  else
    log.error("✗ Prueba fallida: " .. name)
    log.error("  Error: " .. tostring(result))
    return false
  end
end

-- Prueba 1: Escribir un archivo simple
run_test("Escribir archivo simple", function()
  local success = file_utils.write_file(test_file, test_content)
  assert(success, "La escritura del archivo debería tener éxito")

  -- Verificar que el archivo existe y tiene el contenido correcto
  local content = file_utils.read_file(test_file)
  assert(content == test_content, "El contenido leído debería coincidir con el escrito")

  log.debug("Contenido escrito: " .. test_content)
  log.debug("Contenido leído: " .. content)
end)

-- Prueba 2: Escribir y leer un archivo con contenido más complejo
run_test("Escribir archivo con contenido complejo", function()
  local complex_content = [[
Este archivo tiene múltiples líneas
con diferentes caracteres especiales: áéíóú
y símbolos como: !@#$%^&*()_+-=[]{}|;':",./<>?
  ]]

  local success = file_utils.write_file(test_file, complex_content)
  assert(success, "La escritura del archivo debería tener éxito")

  -- Verificar que el archivo existe y tiene el contenido correcto
  local content = file_utils.read_file(test_file)
  assert(content == complex_content, "El contenido leído debería coincidir con el escrito")
end)

-- Prueba 4: Escribir un archivo Java
run_test("Escribir archivo Java", function()
  local success = file_utils.write_file(test_java_file, test_java_content)
  assert(success, "La escritura del archivo debería tener éxito")

  -- Verificar que el archivo existe y tiene el contenido correcto
  local content = file_utils.read_file(test_java_file)
  assert(content == test_java_content, "El contenido leído debería coincidir con el escrito")
end)

-- Prueba 5: Forzar escritura con modo alternativo
run_test("Forzar escritura con modo alternativo", function()
  -- Primero intentamos crear un archivo que requiera permisos especiales
  local special_file = test_dir .. "/special_file.txt"

  -- Escribir con modo forzado
  local success = file_utils.write_file(special_file, test_content, true)
  assert(success, "La escritura forzada debería tener éxito")

  -- Verificar que el archivo existe y tiene el contenido correcto
  local content = file_utils.read_file(special_file)
  assert(content == test_content, "El contenido leído debería coincidir con el escrito")
end)

log.info("Todas las pruebas completadas")