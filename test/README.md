# Pruebas para CopilotChatAssist

Este directorio contiene las pruebas automatizadas para el plugin CopilotChatAssist, con especial énfasis en la funcionalidad de documentación de código.

## Estructura de las pruebas

Las pruebas están organizadas por componentes y lenguajes:

- `test_documentation_java.lua`: Pruebas para documentación de archivos Java
- `test_documentation_elixir.lua`: Pruebas para documentación de archivos Elixir
- `run_documentation_tests.lua`: Script para ejecutar todas las pruebas de documentación

## Cómo ejecutar las pruebas

### Usar el script de ejecución

La forma más sencilla de ejecutar las pruebas es usando el script proporcionado:

```bash
./test/run_tests.sh
```

Este script configura correctamente el entorno y ejecuta todas las pruebas.

### Ejecución manual

Para ejecutar todas las pruebas de documentación manualmente:

```bash
# Desde la raíz del proyecto
lua test/run_documentation_tests.lua
```

### Ejecutar pruebas específicas

Para ejecutar pruebas para un lenguaje específico:

```bash
# Desde la raíz del proyecto
lua test/test_documentation_java.lua
lua test/test_documentation_elixir.lua
lua test/test_fix_service_annotation.lua
lua test/test_fix_elixir_controller.lua
```

### Solución de problemas comunes

Si las pruebas fallan con errores de "module not found", asegúrate de:

1. Ejecutar las pruebas desde la raíz del proyecto (no desde el directorio test)
2. Usar el script run_tests.sh que configura correctamente las rutas

## Mocks y simulación del entorno

Las pruebas utilizan mocks para simular el entorno de Neovim:

1. **Mock de vim.api**: Simula las funciones de la API de Neovim
2. **Mock del buffer**: Simula el contenido de archivos para probar la detección y modificación
3. **Mock de log**: Captura mensajes de log para análisis

## Cómo añadir nuevas pruebas

### 1. Añadir casos de prueba a archivos existentes

Para añadir un nuevo caso de prueba a un archivo existente:

1. Crea una nueva función en la tabla `tests`
2. Configura el contenido del buffer de prueba (`mock.buffer_content`)
3. Limpia el estado del mock (`mock.modified_content`, `mock.notifications`, etc.)
4. Carga el módulo de lenguaje correspondiente
5. Ejecuta la funcionalidad a probar
6. Verifica los resultados con `assert`
7. Imprime un mensaje de éxito

Ejemplo:

```lua
tests.nuevo_test = function()
  -- Configurar el buffer
  mock.buffer_content = {
    -- Contenido de ejemplo
  }

  -- Limpiar estado
  mock.modified_content = nil
  mock.notifications = {}
  mock.log_messages = {}

  -- Cargar el módulo
  local handler = require("copilotchatassist.documentation.language.java")

  -- Ejecutar la funcionalidad
  local result = handler.some_function(1, 2, "test")

  -- Verificar resultados
  assert(result, "La función debería devolver true")

  print("✅ Test nuevo_test pasado")
end
```

### 2. Crear nuevos archivos de prueba

Para añadir pruebas para un nuevo lenguaje o componente:

1. Crea un nuevo archivo `test_[componente].lua`
2. Copia la estructura básica de mocks y configuración de los archivos existentes
3. Implementa tus casos de prueba específicos
4. Añade el archivo al listado en `run_documentation_tests.lua`

## Mejores prácticas

- **Aislar pruebas**: Cada prueba debe ser independiente y limpiar su estado
- **Mensajes claros**: Usa mensajes de error descriptivos en los `assert`
- **Cobertura completa**: Prueba casos normales, casos límite y casos de error
- **Nombrado significativo**: Usa nombres claros para las funciones de prueba

## Solución de problemas

### Error en las pruebas

Si las pruebas fallan, los mensajes de error incluirán:
- El nombre de la prueba que falló
- El mensaje de error específico
- La línea donde ocurrió el fallo

### Mocks incorrectos

Si sospechas que el mock no está funcionando correctamente:
1. Añade logs temporales (`print()`) para depurar
2. Verifica que los mocks estén configurados correctamente antes de cada prueba
3. Asegúrate de que los requerimientos del módulo sean correctos

## Desarrollos futuros

- Integración con CI/CD
- Métricas de cobertura de pruebas
- Pruebas para más lenguajes de programación
- Pruebas para otros componentes del plugin