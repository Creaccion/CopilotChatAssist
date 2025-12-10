#!/bin/bash

# Este script ejecuta las pruebas de documentación desde la línea de comando

# Determinar la ruta absoluta del directorio actual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Cambiar al directorio raíz del proyecto para garantizar que las rutas sean correctas
cd "$PROJECT_ROOT" || { echo "Error al cambiar al directorio del proyecto"; exit 1; }

echo "Ejecutando pruebas desde: $PROJECT_ROOT"
echo

# Verificar que Lua está instalado
if ! command -v lua &> /dev/null; then
    echo "Error: Lua no está instalado o no está en el PATH."
    echo "Por favor, instala Lua 5.1+ para ejecutar estas pruebas."
    exit 1
fi

# Ejecutar todas las pruebas
lua test/run_documentation_tests.lua

# Guardar el código de salida
exit_code=$?

# Mensaje final
if [ $exit_code -eq 0 ]; then
    echo -e "\n\033[32mTodas las pruebas pasaron exitosamente\033[0m"
else
    echo -e "\n\033[31mAlgunas pruebas fallaron\033[0m"
fi

exit $exit_code