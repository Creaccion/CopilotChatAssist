-- Script para ejecutar todas las pruebas de documentación
-- Permite ejecutar todas las pruebas desde un único punto de entrada

-- Añadir ruta de búsqueda para encontrar los módulos de CopilotChatAssist
local script_path = debug.getinfo(1).source:match("@(.*/)") or ""
script_path = script_path:sub(1, -6)  -- Quitar 'test/'
package.path = script_path .. "lua/?.lua;" .. package.path
package.path = script_path .. "?.lua;" .. package.path

-- Función para ejecutar un archivo de prueba específico
local function run_test_file(file_path)
  local success, err = pcall(function()
    -- Limpiar el ambiente para evitar contaminación entre archivos de prueba
    for k, v in pairs(package.loaded) do
      if k:match("^copilotchatassist%.") then
        package.loaded[k] = nil
      end
    end

    print("\n\n=== EJECUTANDO " .. file_path .. " ===")
    dofile(file_path)
  end)

  if not success then
    print("❌ Error ejecutando " .. file_path .. ": " .. tostring(err))
    return false
  end

  return true
end

-- Listado de archivos de prueba
local test_files = {
  -- Pruebas generales
  "test/test_documentation_java.lua",
  "test/test_documentation_elixir.lua",

  -- Pruebas específicas para problemas detectados
  "test/test_fix_service_annotation.lua",
  "test/test_fix_elixir_controller.lua",
  -- Añadir aquí nuevos archivos de prueba cuando se creen
}

-- Ejecutar todas las pruebas
print("\n==================================================")
print("=== SUITE DE PRUEBAS DE DOCUMENTACIÓN INICIADA ===")
print("==================================================\n")

local all_passed = true
local total_files = #test_files
local passed_files = 0

for _, file_path in ipairs(test_files) do
  if run_test_file(file_path) then
    passed_files = passed_files + 1
  else
    all_passed = false
  end
end

print("\n==================================================")
print("=== RESULTADOS DE LA SUITE DE PRUEBAS ===")
print("==================================================")

if all_passed then
  print("✅ TODAS LAS PRUEBAS PASARON EXITOSAMENTE")
  print("Archivos de prueba ejecutados: " .. passed_files .. "/" .. total_files)
else
  print("❌ ALGUNAS PRUEBAS FALLARON")
  print("Archivos de prueba exitosos: " .. passed_files .. "/" .. total_files)
end

print("\n==================================================")

-- Devolver código de éxito/error para scripts de CI
if not all_passed then
  os.exit(1)
end