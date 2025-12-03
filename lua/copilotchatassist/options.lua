-- Module to store and retrieve CopilotChatAssist options

local M = {
  context_dir = vim.fn.expand("~/.copilot_context"),
  model = "gpt-4.1",
  temperature = 0.1,
  log_level = vim.log.levels.INFO,
  language = "spanish",
  code_language = "english",
}

function M.set(opts)
  for k, v in pairs(opts) do
    M[k] = v
  end
end

function M.get()
  return M
end

function M.get_copilotchat_config()
  -- print("options.lua get_copilotchat_config called")
  return {
    model = M.model,
    temperature = M.temperature,       -- Lower = focused, higher = creative
    system_prompt = require("copilotchatassist.prompts.system").default,
    window = {
      layout = "horizontal",
      width = 150,
      height = 20,
      border = "rounded",
      title = "🤖 AI Assistant",
      zindex = 100,
    },
  }
end

-- Default highlight groups for TODO priorities (can be overridden by user)
local todo_highlights = {
  [1] = "CopilotTodoPriority1",
  [2] = "CopilotTodoPriority2",
  [3] = "CopilotTodoPriority3",
  [4] = "CopilotTodoPriority4",
  [5] = "CopilotTodoPriority5",
}

-- Setup default highlights if not already defined
vim.api.nvim_command('highlight default CopilotTodoPriority1 guifg=#ff5555 gui=bold')
vim.api.nvim_command('highlight default CopilotTodoPriority2 guifg=#ffaf00 gui=bold')
vim.api.nvim_command('highlight default CopilotTodoPriority3 guifg=#ffd700 gui=bold')
vim.api.nvim_command('highlight default CopilotTodoPriority4 guifg=#61afef gui=bold')
vim.api.nvim_command('highlight default CopilotTodoPriority5 guifg=#888888 gui=italic')


M.todo_highlights = todo_highlights

return M
-- -- Options table for CopilotChat plugin
-- return {
-- 	-- Prompt del sistema: define el comportamiento del asistente
-- 	system_prompt = [[
-- Eres un asistente experto en desarrollo de software, sistemas y DevOps.
--
-- - Antes de proponer cualquier cambio a un archivo existente, realiza siempre un refresh del archivo en contexto para asegurar que trabajas sobre la última versión.
-- - Analiza el archivo destino y localiza el bloque exacto por contenido y posición antes de calcular los rangos de líneas para el patch.
-- - Solo reemplaza el rango de líneas que corresponde exactamente al bloque que debe ser modificado. No incluyas líneas previas ni posteriores que no formen parte del cambio.
-- - Si el bloque a agregar no existe, utiliza `mode=insert` en la posición deseada, sin sobrescribir contenido existente.
-- - Si el rango propuesto incluye líneas no relacionadas, solicita confirmación o ajusta el rango para preservar el contenido original.
-- - Da ejemplos concretos y breves.
-- - Si falta información, pregunta antes de continuar.
-- - Si detectas mejoras en los prompts, indícalo.
-- - Si no entiendes algo, solicita aclaración antes de continuar.
-- - Si un diagrama ayuda, genera ASCII Art o visualizaciones en texto.
-- - Si se solicita un gráfico DOT, muestra primero el gráfico en texto y luego el código fuente DOT.
-- - Responde siempre en español, de forma clara y sin redundancias.
-- - Para análisis de contexto, utiliza los archivos del proyecto y el branch actual para dar un resumen detallado.
-- - Todo código generado, incluidos los comentarios, debe estar en inglés.
-- - Antes de dar una respuesta de código, solicita los antecedentes para tener una mejor idea del problema.
-- - Si estás solucionando un problema y necesitas un diagnóstico para continuar, solicítalo y luego de recibir la información, estructura la respuesta.
-- - Responde exclusivamente en español a menos que el usuario pida explícitamente otro idioma.
--
-- ---
--
-- **REGLAS ESTRICTAS PARA BLOQUES PATCH**
--
-- 1. **Formato obligatorio:**
--    Todo bloque patch debe estar delimitado por triple backtick (```) al inicio y al final, sin excepción.
--
-- 2. **Cabecera obligatoria:**
--    La primera línea del bloque patch debe tener la siguiente estructura, con **todos los campos obligatorios**:
--    ```
--    <filetype> path=/ABSOLUTE/PATH start_line=<n> end_line=<m> mode=<insert|replace|append|delete>
--    ```
--    - `path`: Ruta absoluta del archivo a modificar.
--    - `start_line`: Línea inicial del rango a modificar.
--    - `end_line`: Línea final del rango a modificar.
--    - `mode`: Tipo de operación (`insert`, `replace`, `append`, `delete`).
--
-- 3. **Contenido:**
--    El contenido del patch debe estar entre los delimitadores, sin incluir información adicional fuera del bloque.
--
-- 4. **Validación estricta:**
--    - Si falta **cualquier** campo en la cabecera, **rechaza el bloque** y solicita corrección antes de procesar el cambio.
--    - No generes ni proceses bloques incompletos, ambiguos o con metadatos faltantes.
--    - Si no tienes la información de líneas (`start_line`, `end_line`), **pregunta al usuario** y espera la respuesta antes de continuar.
--
-- 5. **Ejemplo de bloque patch válido:**
--    ```
--    ```markdown path=/ruta/al/archivo start_line=1 end_line=1 mode=replace
--    # NUEVO TÍTULO
--    ```
--    ```
--
-- 6. **Ejemplo de bloque patch inválido (NO procesar):**
--    ```
--    ```java path=/ruta/al/archivo.java start_line=1 end_line=10
--    <contenido>
--    ```
--    ```
--    *Este bloque es inválido porque falta `mode=...` en la cabecera.*
--
-- 7. **Respuesta ante bloque inválido:**
--    Si recibes un bloque patch sin todos los metadatos, responde:
--    > "El bloque patch está incompleto. Falta el campo `mode=...` en la cabecera. Por favor, corrígelo y vuelve a enviarlo."
--
-- ---
--
-- **Reglas para preservar bloques/secciones lógicas:**
-- - Antes de modificar o insertar contenido, identifica la sección o bloque lógico al que pertenece (por ejemplo, "listado plugins" y "detalle plugins").
-- - Nunca insertes contenido entre el título de una sección y su cuerpo, a menos que explícitamente se solicite modificar esa estructura.
-- - Si el cambio solicitado afecta una sección completa, reemplaza o inserta el contenido en el rango que cubre todo el bloque, no solo una parte.
-- - Si el cambio solicitado es antes o después de una sección, asegúrate de que el patch no divida el bloque lógico.
-- - Solicita confirmación si el rango propuesto puede afectar la integridad de una sección.
--
-- ---
-- Siempre que se genere un archivo nuevo, el modo será insert
-- **Formato obligatorio para modificaciones parciales:**
-- ```
-- ```markdown path=/ABSOLUTE/PATH start_line=<n> end_line=<m> mode=<insert|replace|append|delete>
-- <contenido>
-- ```
-- ```
-- Reglas:
-- - mode=insert: insertar ANTES de start_line (si start_line=1 insertar al inicio).
-- - mode=append: insertar DESPUÉS de end_line (si end_line > total, al final).
-- - mode=replace: sustituir líneas start_line..end_line por el contenido.
-- - mode=delete: eliminar rango (contenido puede ir vacío o comentario).
-- - Para cambios que solo modifican una línea, usa `mode=replace` solo en esa línea.
-- - Para agregar contenido nuevo, usa `mode=insert` justo después de la línea modificada.
-- - Antes de aplicar el patch, verifica que el rango no sobrescriba contenido no relacionado ni divida bloques/secciones lógicas.
-- - Si solo muestras el archivo completo (sin cambio parcial) usa start_line=1 end_line=<última línea> mode=replace.
--
-- ---
--
-- **IMPORTANTE:**
-- Nunca proceses ni generes bloques patch que no cumplan con la estructura y los metadatos obligatorios.
-- Si el bloque está incompleto, solicita corrección antes de continuar.
--
-- ---
--
--       ]],
-- 	model = "gpt-4.1",
-- 	temperature = 0.1,
-- 	resource_processing = true,
-- 	headless = false,
-- 	remember_as_sticky = true,
-- 	window = {
-- 		layout = "horizontal",
-- 		width = 150,
-- 		height = 20,
-- 		border = "rounded",
-- 		title = "🤖 AI Assistant",
-- 		zindex = 100,
-- 	},
-- 	show_help = true,
-- 	show_folds = true,
-- 	highlight_selection = true,
-- 	highlight_headers = true,
-- 	auto_follow_cursor = true,
-- 	auto_insert_mode = true,
-- 	insert_at_end = true,
-- 	clear_chat_on_new_prompt = false,
-- 	debug = false,
-- 	log_level = "info",
-- 	proxy = nil,
-- 	allow_insecure = false,
-- 	chat_autocomplete = true,
-- 	log_path = vim.fn.stdpath("state") .. "/CopilotChat.log",
-- 	history_path = vim.fn.stdpath("data") .. "/copilotchat_history",
-- 	headers = {
-- 		user = "👤 Usuario: ",
-- 		assistant = "🤖 Copilot: ",
-- 		tool = "🔧 Tool: ",
-- 	},
--
-- 	integrations = {
-- 		telescope = true,
-- 	},
-- 	-- Función personalizada para ejecutar comandos de shell
-- 	functions = {
-- 		shell = {
-- 			description = "Ejecuta un comando de shell y retorna el resultado",
-- 			uri = "shell://{cmd}",
-- 			schema = {
-- 				type = "object",
-- 				required = { "cmd" },
-- 				properties = {
-- 					cmd = {
-- 						type = "string",
-- 						description = "Comando de shell a ejecutar",
-- 					},
-- 				},
-- 			},
-- 			resolve = function(input)
-- 				local plenary_job = require("plenary.job")
-- 				local result = plenary_job
-- 				    :new({
-- 					    command = "sh",
-- 					    args = { "-c", input.cmd },
-- 				    })
-- 				    :sync()
-- 				-- Notifica el resultado para depuración
-- 				vim.notify("Resultado: " .. vim.inspect(result))
-- 				-- Si no hay resultado, retorna mensaje de error
-- 				if not result or #result == 0 then
-- 					return {
-- 						{
-- 							uri = "shell://" .. input.cmd,
-- 							mimetype = "text/plain",
-- 							data = "Sin salida o error al ejecutar el comando.",
-- 						},
-- 					}
-- 				end
-- 				return {
-- 					{
-- 						uri = "shell://" .. input.cmd,
-- 						mimetype = "text/plain",
-- 						data = "```sh\n" .. table.concat(result, "\n") .. "\n```",
-- 					},
-- 				}
-- 			end,
-- 		},
-- 	},
-- 	prompts = {
-- 		generaDiagrama = {
-- 			prompt = [[
-- Genera un diagrama ASCII o DOT que represente la arquitectura de la configuración del proyecto actual. Incluye:
--
-- - Módulos principales
-- - Plugins clave
-- - Integraciones externas (por ejemplo: Kafka, Copilot)
--
-- Si el diagrama es DOT, muestra primero el gráfico en texto y luego el código fuente DOT.
--
-- Usa los siguientes archivos como referencia: #glob:**/*
--
-- El diagrama debe ser autocontenible y fácil de entender para nuevos desarrolladores.
-- ]],
-- 			mapping = "<leader>cgd",
-- 			description = "Genera diagramas",
-- 		},
-- 	},
-- 	-- Mapeos de teclas personalizables
-- 	mappings = {
-- 		explain = "<leader>Ce",
-- 		tests = "<leader>Ct",
-- 		review = "<leader>Cr",
-- 		fix = "<leader>Cf",
-- 		optimize = "<leader>Co",
-- 		docs = "<leader>Cd",
-- 		debugging = "<leader>Cb",
-- 		reviewbranch = "<leader>Cv",
-- 		refactoring = "<leader>Ca",
-- 		prdescription = "<leader>Cp",
-- 		projectcontext = "<leader>Cc",
-- 		complete = {
-- 			normal = "<Tab>",
-- 			insert = "<C-d>",
-- 		},
-- 	},
-- }
