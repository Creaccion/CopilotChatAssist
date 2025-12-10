# Sistema de Gestión de Patches

El sistema de gestión de patches es una funcionalidad que permite extraer, gestionar y aplicar automáticamente fragmentos de código generados por CopilotChat a archivos del proyecto.

## Índice

- [Conceptos clave](#conceptos-clave)
- [Formato de patches](#formato-de-patches)
- [Visualización de patches](#visualización-de-patches)
- [Integración con TODOs](#integración-con-todos)
- [Comandos disponibles](#comandos-disponibles)
- [Flujo de trabajo recomendado](#flujo-de-trabajo-recomendado)

## Conceptos clave

El sistema de patches se basa en estos conceptos fundamentales:

1. **Patch**: Unidad básica de modificación de código con propiedades como archivo destino, líneas de inicio/fin, modo y contenido
2. **Cola de patches**: Estructura centralizada que mantiene los patches pendientes de aplicación
3. **Parser de patches**: Componente que extrae y valida bloques de patches de las respuestas de CopilotChat
4. **Gestor de archivos**: Módulo que aplica los patches a los archivos de manera segura
5. **Interfaz visual**: Ventana interactiva para gestionar y aplicar patches

## Formato de patches

Los patches siguen un formato específico en las respuestas de CopilotChat:

```
```<lenguaje> path=/ruta/al/archivo start_line=<num> end_line=<num> mode=<modo>
// código a insertar/modificar
```end
```

Donde:

- **`<lenguaje>`**: Identificador del lenguaje de programación (javascript, python, lua, etc.)
- **`path`**: Ruta absoluta al archivo donde se aplicará el patch
- **`start_line`**: Línea de inicio para la operación
- **`end_line`**: Línea final para la operación
- **`mode`**: Modo de aplicación:
  - `replace`: Reemplaza el contenido entre las líneas indicadas
  - `insert`: Inserta contenido en la línea indicada
  - `append`: Añade contenido después de la línea indicada
  - `delete`: Elimina las líneas indicadas

## Visualización de patches

Para ver y gestionar los patches disponibles, usa:

```
:CopilotPatchesWindow
```

Esto abrirá una ventana con:

- Lista de todos los patches pendientes
- Información sobre archivo y rango de líneas
- Estado actual de cada patch (pendiente, aplicado, fallido)

### Atajos de teclado en la ventana de patches

| Tecla | Acción |
|-------|--------|
| `<CR>` (Enter) | Ver detalles completos del patch |
| `a` | Aplicar el patch seleccionado |
| `d` | Eliminar el patch seleccionado |
| `r` | Refrescar la vista |
| `?` | Mostrar ayuda con todos los atajos |
| `q` | Cerrar la ventana |

## Integración con TODOs

El sistema de patches está integrado con el sistema de TODOs, permitiendo:

1. Seleccionar una tarea pendiente en la ventana de TODOs
2. Presionar `i` para solicitar la implementación a CopilotChat
3. Los patches generados se añaden automáticamente a la cola
4. Opcionalmente ver y aplicar los patches inmediatamente

Este flujo facilita la implementación semi-automatizada de las tareas:

```
Tarea pendiente → Solicitar implementación → Revisar patches → Aplicar cambios → Tarea completada
```

## Comandos disponibles

| Comando | Descripción |
|---------|-------------|
| `:CopilotPatchesWindow` | Muestra la ventana de gestión de patches |
| `:CopilotPatchesShowQueue` | Muestra resumen de patches pendientes |
| `:CopilotPatchesApply` | Aplica todos los patches pendientes |
| `:CopilotPatchesClearQueue` | Elimina todos los patches de la cola |
| `:CopilotPatchesProcessBuffer` | Procesa el buffer actual buscando patches |

## Flujo de trabajo recomendado

Para aprovechar al máximo el sistema de patches:

1. **Generación de patches**:
   - Solicita implementaciones a CopilotChat (directamente o desde TODOs)
   - Los patches se detectan y añaden automáticamente a la cola

2. **Revisión de patches**:
   - Abre la ventana de patches con `:CopilotPatchesWindow`
   - Revisa cada patch para asegurarte de que es correcto
   - Ver detalles completos con `Enter`

3. **Aplicación de patches**:
   - Aplica patches individuales con `a`
   - O aplica todos los patches con `:CopilotPatchesApply`
   - Confirma cada aplicación cuando se muestre la vista previa

4. **Integración con flujo de trabajo**:
   - Usa patches como parte del proceso de implementación de tareas
   - Combina con el sistema de TODOs para un flujo completo

## Uso desde código Lua

También puedes interactuar con el sistema de patches programáticamente:

```lua
-- Obtener módulo de patches
local patches = require("copilotchatassist.patches")

-- Procesar texto en busca de patches
local count = patches.process_copilot_response(text)

-- Mostrar ventana de patches
patches.show_patch_window()

-- Aplicar todos los patches
patches.apply_patch_queue()
```

## Notas de seguridad

- Todos los patches se muestran para previsualización antes de ser aplicados
- Se requiere confirmación explícita para aplicar cualquier cambio
- El sistema valida las rutas y metadatos para evitar cambios no deseados