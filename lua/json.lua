-- Calradia Online: Deterministic pure-Lua JSON encoder/decoder (Lua 5.1 / LuaJIT 2.1)
-- Sorted keys on encode ensure deterministic file outputs and state hashes.

local json = {}

local escape_map = {
  ['"']  = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local function escape_char(c)
  return escape_map[c] or string.format("\\u%04x", string.byte(c))
end

local function encode_string(s)
  return '"' .. tostring(s):gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function is_array(tbl)
  local count = 0
  local max_idx = 0
  for k, _ in pairs(tbl) do
    if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
      return false, 0
    end
    if k > max_idx then
      max_idx = k
    end
    count = count + 1
  end
  if max_idx ~= count then
    return false, 0
  end
  return true, count
end

local function encode_value(val, indent, depth, stack)
  local t = type(val)
  if val == nil or val == json.null then
    return "null"
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "number" then
    if val ~= val or val <= -math.huge or val >= math.huge then
      return "null"
    end
    if math.floor(val) == val and val >= -9007199254740991 and val <= 9007199254740991 then
      return string.format("%.0f", val)
    end
    return string.format("%.14g", val)
  elseif t == "string" then
    return encode_string(val)
  elseif t == "table" then
    if stack[val] then
      error("json.encode: circular reference detected")
    end
    stack[val] = true
    local arr, len = is_array(val)
    local pad = indent and string.rep("  ", depth + 1) or ""
    local close_pad = indent and string.rep("  ", depth) or ""
    local sep = indent and ",\n" or ","
    local kv_sep = indent and ": " or ":"
    local parts = {}

    if arr then
      if len == 0 then
        stack[val] = nil
        return "[]"
      end
      for i = 1, len do
        parts[i] = pad .. encode_value(val[i], indent, depth + 1, stack)
      end
      stack[val] = nil
      if indent then
        return "[\n" .. table.concat(parts, sep) .. "\n" .. close_pad .. "]"
      end
      return "[" .. table.concat(parts, sep) .. "]"
    else
      local keys = {}
      for k, _ in pairs(val) do
        keys[#keys + 1] = k
      end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      if #keys == 0 then
        stack[val] = nil
        return "{}"
      end
      for i = 1, #keys do
        local k = keys[i]
        local encoded_v = encode_value(val[k], indent, depth + 1, stack)
        parts[#parts + 1] = pad .. encode_string(tostring(k)) .. kv_sep .. encoded_v
      end
      stack[val] = nil
      if indent then
        return "{\n" .. table.concat(parts, sep) .. "\n" .. close_pad .. "}"
      end
      return "{" .. table.concat(parts, sep) .. "}"
    end
  else
    error("json.encode: unsupported type " .. t)
  end
end

json.null = setmetatable({}, { __tostring = function() return "null" end })

function json.encode(val, pretty)
  return encode_value(val, pretty and true or false, 0, {})
end

-- Decoder
local function skip_ws(str, idx)
  local _, e = str:find("^[ \t\r\n]*", idx)
  return (e or idx - 1) + 1
end

local parse_value

local function codepoint_to_utf8(n)
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(0xc0 + math.floor(n / 64), 0x80 + (n % 64))
  elseif n <= 0xffff then
    return string.char(
      0xe0 + math.floor(n / 4096),
      0x80 + (math.floor(n / 64) % 64),
      0x80 + (n % 64)
    )
  else
    return string.char(
      0xf0 + math.floor(n / 262144),
      0x80 + (math.floor(n / 4096) % 64),
      0x80 + (math.floor(n / 64) % 64),
      0x80 + (n % 64)
    )
  end
end

local unescape_map = {
  ['"']  = '"',
  ['\\'] = '\\',
  ['/']  = '/',
  ['b']  = '\b',
  ['f']  = '\f',
  ['n']  = '\n',
  ['r']  = '\r',
  ['t']  = '\t',
}

local function parse_string(str, idx)
  idx = idx + 1 -- skip opening quote
  local out = {}
  local len = #str
  while idx <= len do
    local c = str:sub(idx, idx)
    if c == '"' then
      return table.concat(out), idx + 1
    elseif c == '\\' then
      idx = idx + 1
      local esc = str:sub(idx, idx)
      if esc == "u" then
        local hex = str:sub(idx + 1, idx + 4)
        if not hex:match("^%x%x%x%x$") then
          error("json.decode: invalid unicode escape at " .. idx)
        end
        out[#out + 1] = codepoint_to_utf8(tonumber(hex, 16))
        idx = idx + 5
      elseif unescape_map[esc] then
        out[#out + 1] = unescape_map[esc]
        idx = idx + 1
      else
        error("json.decode: invalid escape '\\" .. esc .. "' at " .. idx)
      end
    else
      local next_special = str:find('["\\]', idx)
      if not next_special then
        error("json.decode: unterminated string")
      end
      out[#out + 1] = str:sub(idx, next_special - 1)
      idx = next_special
    end
  end
  error("json.decode: unterminated string at end of input")
end

local function parse_number(str, idx)
  local _, e, num_s = str:find("^(-?%d+%.?%d*[eE]?[+-]?%d*)", idx)
  if not num_s then
    error("json.decode: invalid number at " .. idx)
  end
  local n = tonumber(num_s)
  if not n then
    error("json.decode: malformed number '" .. num_s .. "' at " .. idx)
  end
  return n, e + 1
end

local function parse_array(str, idx)
  idx = skip_ws(str, idx + 1)
  local res = {}
  if str:sub(idx, idx) == "]" then
    return res, idx + 1
  end
  local i = 1
  while true do
    local val
    val, idx = parse_value(str, idx)
    res[i] = val
    i = i + 1
    idx = skip_ws(str, idx)
    local ch = str:sub(idx, idx)
    if ch == "]" then
      return res, idx + 1
    elseif ch ~= "," then
      error("json.decode: expected ',' or ']' at " .. idx)
    end
    idx = skip_ws(str, idx + 1)
  end
end

local function parse_object(str, idx)
  idx = skip_ws(str, idx + 1)
  local res = {}
  if str:sub(idx, idx) == "}" then
    return res, idx + 1
  end
  while true do
    if str:sub(idx, idx) ~= '"' then
      error("json.decode: expected string key at " .. idx)
    end
    local key, val
    key, idx = parse_string(str, idx)
    idx = skip_ws(str, idx)
    if str:sub(idx, idx) ~= ":" then
      error("json.decode: expected ':' at " .. idx)
    end
    idx = skip_ws(str, idx + 1)
    val, idx = parse_value(str, idx)
    if val ~= json.null then
      res[key] = val
    end
    idx = skip_ws(str, idx)
    local ch = str:sub(idx, idx)
    if ch == "}" then
      return res, idx + 1
    elseif ch ~= "," then
      error("json.decode: expected ',' or '}' at " .. idx)
    end
    idx = skip_ws(str, idx + 1)
  end
end

parse_value = function(str, idx)
  idx = skip_ws(str, idx)
  local ch = str:sub(idx, idx)
  if ch == '"' then
    return parse_string(str, idx)
  elseif ch == "{" then
    return parse_object(str, idx)
  elseif ch == "[" then
    return parse_array(str, idx)
  elseif ch == "t" and str:sub(idx, idx + 3) == "true" then
    return true, idx + 4
  elseif ch == "f" and str:sub(idx, idx + 4) == "false" then
    return false, idx + 5
  elseif ch == "n" and str:sub(idx, idx + 3) == "null" then
    return nil, idx + 4
  elseif ch == "-" or (ch >= "0" and ch <= "9") then
    return parse_number(str, idx)
  end
  error("json.decode: unexpected character '" .. tostring(ch) .. "' at " .. idx)
end

function json.decode(str)
  if type(str) ~= "string" or str == "" then
    error("json.decode: expected non-empty JSON string")
  end
  local val, idx = parse_value(str, 1)
  idx = skip_ws(str, idx)
  if idx <= #str then
    error("json.decode: trailing characters at " .. idx)
  end
  return val
end

return json
