-- Módulo de utilidades para codificación y decodificación en Base64
-- Implementación básica para codificar credenciales en la integración de Jira

local M = {}

-- Tabla de caracteres para codificación Base64
local b64chars = {
  [0] = 'A', [1] = 'B', [2] = 'C', [3] = 'D', [4] = 'E', [5] = 'F', [6] = 'G', [7] = 'H',
  [8] = 'I', [9] = 'J', [10] = 'K', [11] = 'L', [12] = 'M', [13] = 'N', [14] = 'O', [15] = 'P',
  [16] = 'Q', [17] = 'R', [18] = 'S', [19] = 'T', [20] = 'U', [21] = 'V', [22] = 'W', [23] = 'X',
  [24] = 'Y', [25] = 'Z', [26] = 'a', [27] = 'b', [28] = 'c', [29] = 'd', [30] = 'e', [31] = 'f',
  [32] = 'g', [33] = 'h', [34] = 'i', [35] = 'j', [36] = 'k', [37] = 'l', [38] = 'm', [39] = 'n',
  [40] = 'o', [41] = 'p', [42] = 'q', [43] = 'r', [44] = 's', [45] = 't', [46] = 'u', [47] = 'v',
  [48] = 'w', [49] = 'x', [50] = 'y', [51] = 'z', [52] = '0', [53] = '1', [54] = '2', [55] = '3',
  [56] = '4', [57] = '5', [58] = '6', [59] = '7', [60] = '8', [61] = '9', [62] = '+', [63] = '/'
}

-- Tabla inversa para decodificación
local b64decodes = {}
for k, v in pairs(b64chars) do
  b64decodes[v] = k
end

-- Codificar string en base64
function M.encode(data)
  if not data then return nil end

  local bytes = {}
  for i = 1, #data do
    bytes[i] = data:byte(i)
  end

  local result = {}
  local padding = #data % 3
  local offset = 1

  while offset <= #bytes - padding do
    local a, b, c = bytes[offset], bytes[offset + 1], bytes[offset + 2]
    local triple = (a << 16) + (b << 8) + c

    for i = 0, 3 do
      local index = (triple >> ((3 - i) * 6)) & 0x3F
      result[#result + 1] = b64chars[index]
    end

    offset = offset + 3
  end

  if padding == 1 then
    local a = bytes[offset]
    local triple = (a << 16)

    for i = 0, 1 do
      local index = (triple >> ((3 - i) * 6)) & 0x3F
      result[#result + 1] = b64chars[index]
    end

    result[#result + 1] = '='
    result[#result + 1] = '='
  elseif padding == 2 then
    local a, b = bytes[offset], bytes[offset + 1]
    local triple = (a << 16) + (b << 8)

    for i = 0, 2 do
      local index = (triple >> ((3 - i) * 6)) & 0x3F
      result[#result + 1] = b64chars[index]
    end

    result[#result + 1] = '='
  end

  return table.concat(result, "")
end

-- Decodificar string base64
function M.decode(data)
  if not data then return nil end

  -- Eliminar padding
  data = data:gsub("=", "")

  -- Verificar longitud válida
  if #data % 4 > 0 then return nil end

  local result = {}
  local sextet = {}

  for i = 1, #data do
    local char = data:sub(i, i)
    if b64decodes[char] then
      sextet[#sextet + 1] = b64decodes[char]
    end
  end

  for i = 1, #sextet, 4 do
    local a, b, c, d = sextet[i] or 0, sextet[i+1] or 0, sextet[i+2] or 0, sextet[i+3] or 0

    local triple = (a << 18) + (b << 12) + (c << 6) + d

    local byte1 = (triple >> 16) & 0xFF
    result[#result + 1] = string.char(byte1)

    if i+1 <= #sextet then
      local byte2 = (triple >> 8) & 0xFF
      result[#result + 1] = string.char(byte2)
    end

    if i+2 <= #sextet then
      local byte3 = triple & 0xFF
      result[#result + 1] = string.char(byte3)
    end
  end

  return table.concat(result, "")
end

return M