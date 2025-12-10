#!/bin/bash

# Script para ejecutar las pruebas de validación continua
# Este script verifica que las correcciones implementadas siguen funcionando correctamente

# Determinar la ruta absoluta del directorio actual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Cambiar al directorio raíz del proyecto para garantizar que las rutas sean correctas
cd "$PROJECT_ROOT" || { echo "Error al cambiar al directorio del proyecto"; exit 1; }

echo "Ejecutando validación desde: $PROJECT_ROOT"
echo

# Verificar que Lua está instalado
if ! command -v lua &> /dev/null; then
    echo "Error: Lua no está instalado o no está en el PATH."
    echo "Por favor, instala Lua 5.1+ para ejecutar estas pruebas."
    exit 1
fi

# Colores para la salida
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Iniciando validación continua de correcciones...${NC}"

# Ejecutar el script de validación continua
lua test/continuous_validation.lua

# Guardar el código de salida
exit_code=$?

# Mensaje final
if [ $exit_code -eq 0 ]; then
    echo -e "\n${GREEN}✅ Todas las validaciones pasaron exitosamente${NC}"

    echo -e "\n${YELLOW}Verificando documentación específica para Java...${NC}"
    lua test/test_fix_service_annotation.lua
    java_exit=$?

    echo -e "\n${YELLOW}Verificando detección de módulos Elixir...${NC}"
    lua test/test_fix_elixir_controller.lua
    elixir_exit=$?

    if [ $java_exit -eq 0 ] && [ $elixir_exit -eq 0 ]; then
        echo -e "\n${GREEN}✅ Todas las pruebas específicas pasaron correctamente${NC}"
        echo -e "\n${GREEN}✓ Sistema de documentación validado correctamente${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Algunas pruebas específicas fallaron${NC}"
        exit 1
    fi
else
    echo -e "\n${RED}❌ La validación continua falló${NC}"
    exit $exit_code
fi