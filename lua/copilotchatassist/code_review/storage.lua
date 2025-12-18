-- Módulo para almacenamiento persistente de comentarios de Code Review
-- Utiliza el sistema de archivos para guardar y cargar revisiones

local M = {}
local log = require("copilotchatassist.utils.log")
local file_utils = require("copilotchatassist.utils.file")
local i18n = require("copilotchatassist.i18n")

-- Constantes
local STORAGE_DIR = vim.fn.stdpath("cache") .. "/copilotchatassist/code_reviews"
local INDEX_FILE = STORAGE_DIR .. "/index.json"

-- Estado del módulo
local state = {
  initialized = false,
  index = {
    reviews = {},  -- Lista de revisiones guardadas
    last_review = nil  -- ID de la última revisión
  }
}

-- Inicializar el sistema de almacenamiento
local function initialize()
  if state.initialized then
    return true
  end

  -- Crear directorio de almacenamiento si no existe
  local success = vim.fn.mkdir(STORAGE_DIR, "p") == 1
  if not success and vim.fn.isdirectory(STORAGE_DIR) ~= 1 then
    log.error(i18n.t("code_review.storage_init_failed", {STORAGE_DIR}))
    return false
  end

  -- Cargar índice si existe
  if vim.fn.filereadable(INDEX_FILE) == 1 then
    local content = file_utils.read_file(INDEX_FILE)
    if content and content ~= "" then
      local success, index = pcall(vim.json.decode, content)
      if success and type(index) == "table" then
        state.index = index
        log.debug(i18n.t("code_review.index_loaded", {#index.reviews}))
      else
        log.warn(i18n.t("code_review.index_parse_failed"))
      end
    end
  end

  state.initialized = true
  return true
end

-- Guardar índice de revisiones
local function save_index()
  if not state.initialized then
    initialize()
  end

  local json_str = vim.json.encode(state.index)
  local success = file_utils.write_file(INDEX_FILE, json_str)

  if not success then
    log.error(i18n.t("code_review.index_save_failed"))
  end

  return success
end

-- Obtener ruta de archivo para una revisión
local function get_review_path(review_id)
  return STORAGE_DIR .. "/review_" .. review_id .. ".json"
end

-- Guardar una revisión completa
function M.save_review(review, comments)
  if not initialize() then
    log.error(i18n.t("code_review.storage_init_failed", {STORAGE_DIR}))
    return false
  end

  if not review or not review.id then
    log.error(i18n.t("code_review.invalid_review"))
    return false
  end

  local review_id = review.id
  local review_path = get_review_path(review_id)

  -- Crear objeto para guardar
  local save_data = {
    review = review,
    comments = comments or {}
  }

  -- Convertir a JSON
  local json_str = vim.json.encode(save_data)

  -- Escribir a archivo
  local success = file_utils.write_file(review_path, json_str)

  if success then
    log.debug(i18n.t("code_review.review_saved", {review_id}))

    -- Actualizar índice
    local exists = false
    for i, r in ipairs(state.index.reviews) do
      if r.id == review_id then
        state.index.reviews[i] = {
          id = review_id,
          timestamp = review.updated_at or review.started_at or os.time(),
          comment_count = #comments
        }
        exists = true
        break
      end
    end

    if not exists then
      table.insert(state.index.reviews, {
        id = review_id,
        timestamp = review.updated_at or review.started_at or os.time(),
        comment_count = #comments
      })
    end

    -- Marcar como última revisión
    state.index.last_review = review_id

    -- Guardar índice actualizado
    save_index()
  else
    log.error(i18n.t("code_review.review_save_failed", {review_id}))
  end

  return success
end

-- Cargar una revisión por ID
function M.load_review(review_id)
  if not initialize() then
    log.error(i18n.t("code_review.storage_init_failed", {STORAGE_DIR}))
    return nil, nil
  end

  local review_path = get_review_path(review_id)

  if vim.fn.filereadable(review_path) ~= 1 then
    log.warn(i18n.t("code_review.review_not_found", {review_id}))
    return nil, nil
  end

  local content = file_utils.read_file(review_path)
  if not content or content == "" then
    log.warn(i18n.t("code_review.review_empty", {review_id}))
    return nil, nil
  end

  local success, data = pcall(vim.json.decode, content)
  if not success or type(data) ~= "table" then
    log.error(i18n.t("code_review.review_parse_failed", {review_id}))
    return nil, nil
  end

  if not data.review or not data.comments then
    log.warn(i18n.t("code_review.review_malformed", {review_id}))
    return nil, nil
  end

  log.debug(i18n.t("code_review.review_loaded", {review_id, #data.comments}))
  return data.review, data.comments
end

-- Cargar la última revisión guardada
function M.load_last_review()
  if not initialize() then
    log.error(i18n.t("code_review.storage_init_failed", {STORAGE_DIR}))
    return nil, nil
  end

  if not state.index.last_review then
    log.warn(i18n.t("code_review.no_last_review"))
    return nil, nil
  end

  return M.load_review(state.index.last_review)
end

-- Listar todas las revisiones disponibles
function M.list_reviews()
  if not initialize() then
    log.error(i18n.t("code_review.storage_init_failed", {STORAGE_DIR}))
    return {}
  end

  -- Ordenar por timestamp (más recientes primero)
  local reviews = vim.deepcopy(state.index.reviews)
  table.sort(reviews, function(a, b)
    return (a.timestamp or 0) > (b.timestamp or 0)
  end)

  return reviews
end

-- Eliminar una revisión
function M.delete_review(review_id)
  if not initialize() then
    log.error(i18n.t("code_review.storage_init_failed", {STORAGE_DIR}))
    return false
  end

  local review_path = get_review_path(review_id)

  -- Eliminar archivo
  local success = os.remove(review_path)

  if success then
    log.debug(i18n.t("code_review.review_deleted", {review_id}))

    -- Actualizar índice
    for i, review in ipairs(state.index.reviews) do
      if review.id == review_id then
        table.remove(state.index.reviews, i)
        break
      end
    end

    -- Actualizar última revisión si era la actual
    if state.index.last_review == review_id then
      if #state.index.reviews > 0 then
        -- Usar la revisión más reciente
        state.index.last_review = state.index.reviews[1].id
      else
        state.index.last_review = nil
      end
    end

    -- Guardar índice actualizado
    save_index()
  else
    log.error(i18n.t("code_review.review_delete_failed", {review_id}))
  end

  return success
end

-- Exportar una revisión completa a un archivo
function M.export_review(review_id, path)
  if not review_id then
    if state.index.last_review then
      review_id = state.index.last_review
    else
      log.error(i18n.t("code_review.no_review_to_export"))
      return false
    end
  end

  local review, comments = M.load_review(review_id)
  if not review or not comments then
    log.error(i18n.t("code_review.review_export_failed", {review_id}))
    return false
  end

  local export_data = {
    review = review,
    comments = comments
  }

  local json_str = vim.json.encode(export_data)
  local success = file_utils.write_file(path, json_str)

  if success then
    log.info(i18n.t("code_review.review_exported", {review_id, path}))
  else
    log.error(i18n.t("code_review.review_export_failed", {review_id}))
  end

  return success
end

return M