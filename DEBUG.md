# Herramientas de Depuración para CopilotChatAssist

Este documento describe las herramientas de depuración disponibles en CopilotChatAssist para diagnosticar problemas de comunicación con CopilotChat, particularmente útiles cuando se encuentran errores como respuestas vacías.

## Comandos de Depuración

Se han añadido dos nuevos comandos que pueden ser ejecutados desde Neovim:

### `:CopilotChatCheckConnection`

Este comando verifica la conexión con CopilotChat enviando un mensaje simple y mostrando la respuesta. Útil para confirmar si la API de CopilotChat está funcionando correctamente.

### `:CopilotChatDebugLogs`

Muestra los archivos de log de depuración en una ventana flotante, permitiéndote inspeccionar:
- El último prompt enviado a CopilotChat
- La respuesta raw recibida de CopilotChat
- Información sobre errores de respuestas vacías
- Otros datos de depuración relevantes

## Archivos de Log

Los archivos de log se guardan en el directorio de caché de Neovim, típicamente en:
```
~/.cache/nvim/copilotchatassist/
```

Los archivos incluyen:
- `last_prompt.txt`: El último prompt enviado a CopilotChat
- `response_raw.txt`: La respuesta cruda recibida de CopilotChat
- `error_nil_response.txt`: Se crea cuando CopilotChat devuelve nil
- `error_empty_response.txt`: Se crea cuando CopilotChat devuelve una cadena vacía
- `last_response.txt`: La última respuesta procesada

## Diagnosticando el Problema de Respuesta Vacía

Si encuentras el error "Error al obtener respuesta de CopilotChat: respuesta vacía", sigue estos pasos:

1. **Verificar la conexión**:
   ```
   :CopilotChatCheckConnection
   ```

   Si este comando no recibe respuesta o recibe una respuesta vacía, confirma que hay problemas con la API de CopilotChat.

2. **Revisar los logs de depuración**:
   ```
   :CopilotChatDebugLogs
   ```

   Examina los archivos de log para ver detalles sobre la comunicación con CopilotChat.

3. **Comprobar el tamaño del prompt**:
   Es posible que prompts muy grandes causen problemas. Comprueba el tamaño del archivo `last_prompt.txt`.

4. **Verificar credenciales de CopilotChat**:
   Asegúrate de que tienes las credenciales correctas y que el acceso a CopilotChat está funcionando.

## Soluciones Posibles

Si encuentras que CopilotChat está devolviendo respuestas vacías, considera estas soluciones:

1. **Reiniciar CopilotChat**: A veces, simplemente reiniciar Neovim puede resolver problemas temporales.

2. **Actualizar credenciales**: Asegúrate de que tus credenciales de GitHub Copilot estén actualizadas.

3. **Dividir archivos grandes**: Si estás documentando archivos muy grandes, considera dividirlos en secciones más pequeñas.

4. **Esperar y reintentar**: A veces, CopilotChat puede estar sobrecargado. Espera unos minutos e intenta nuevamente.

5. **Verificar la conexión a internet**: Asegúrate de tener una conexión a internet estable.

## Información de Depuración para Soporte

Si necesitas reportar un problema a los desarrolladores, proporciona la siguiente información:

1. El mensaje de error exacto que estás recibiendo.
2. El contenido de los archivos de log de depuración (usando `:CopilotChatDebugLogs`).
3. El tamaño y tipo del archivo que estabas intentando documentar.
4. El resultado del comando `:CopilotChatCheckConnection`.

Esta información será de gran ayuda para diagnosticar el problema específico que estás enfrentando.