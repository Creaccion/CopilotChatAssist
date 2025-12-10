#!/bin/bash

# Script para ejecutar las pruebas de formato de documentación
# Este script verifica que el formato de la documentación generada sea correcto

# Determinar la ruta absoluta del directorio actual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Cambiar al directorio raíz del proyecto para garantizar que las rutas sean correctas
cd "$PROJECT_ROOT" || { echo "Error al cambiar al directorio del proyecto"; exit 1; }

echo "Ejecutando verificación de formato desde: $PROJECT_ROOT"
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

echo -e "${YELLOW}Iniciando verificación de formato de documentación...${NC}"

# Ejecutar el script de verificación de formato
lua test/test_documentation_format.lua

# Guardar el código de salida
exit_code=$?

# Mensaje final
if [ $exit_code -eq 0 ]; then
    echo -e "\n${GREEN}✅ La verificación de formato pasó exitosamente${NC}"
    echo -e "\n${GREEN}✓ El formato de documentación es correcto${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Se encontraron problemas de formato en la documentación${NC}"
    echo -e "\n${YELLOW}Recomendaciones:${NC}"
    echo -e "1. Revisar el posicionamiento de la documentación en Java"
    echo -e "2. Verificar que no haya documentación duplicada"
    echo -e "3. Comprobar que las secciones de documentación en Elixir no estén vacías"
    exit $exit_code
fi