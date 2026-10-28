-- Calradia Online: FIPS 180-4 SHA-256 & RFC 2104 HMAC-SHA256 for LuaJIT 2.1 / Lua 5.1
-- Used for Steam-independent player identity verification and save integrity checksums.

local sha256 = {}

local ok_bit, bit = pcall(require, "bit")

local band, bor, bxor, bnot, rshift, lshift, ror

if ok_bit and bit then
  local tobit = bit.tobit
  band = function(a, b) return bit.band(a, b) end
  bor  = function(a, b) return bit.bor(a, b) end
  bxor = function(a, b) return bit.bxor(a, b) end
  bnot = function(a) return bit.bnot(a) end
  rshift = function(a, n) return bit.rshift(a, n) end
  lshift = function(a, n) return bit.lshift(a, n) end
  ror = function(a, n) return bit.ror(tobit(a), n) end
else
  -- Pure Lua arithmetic fallback if bit library is absent
  local MOD = 4294967296
  band = function(a, b)
    a = a % MOD; b = b % MOD
    local res, p = 0, 1
    for _ = 1, 32 do
      local ra, rb = a % 2, b % 2
      if ra == 1 and rb == 1 then res = res + p end
      a = (a - ra) / 2; b = (b - rb) / 2; p = p * 2
      if a == 0 or b == 0 then break end
    end
    return res
  end
  bxor = function(a, b)
    a = a % MOD; b = b % MOD
    local res, p = 0, 1
    for _ = 1, 32 do
      local ra, rb = a % 2, b % 2
      if ra ~= rb then res = res + p end
      a = (a - ra) / 2; b = (b - rb) / 2; p = p * 2
      if a == 0 and b == 0 then break end
    end
    return res
  end
  bor = function(a, b)
    a = a % MOD; b = b % MOD
    return (a + b - band(a, b)) % MOD
  end
  bnot = function(a)
    return (MOD - 1 - (a % MOD)) % MOD
  end
  rshift = function(a, n)
    return math.floor((a % MOD) / (2 ^ n))
  end
  lshift = function(a, n)
    return ((a % MOD) * (2 ^ n)) % MOD
  end
  ror = function(a, n)
    a = a % MOD
    return bor(rshift(a, n), lshift(a, 32 - n))
  end
end

local function u32(x)
  if x < 0 then
    return x + 4294967296
  end
  return x % 4294967296
end

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local H0 = {
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

local function num_to_be32(n)
  n = u32(n)
  return string.char(
    math.floor(n / 16777216) % 256,
    math.floor(n / 65536) % 256,
    math.floor(n / 256) % 256,
    n % 256
  )
end

function sha256.digest_raw(msg)
  msg = tostring(msg or "")
  local len = #msg
  local bit_len_hi = math.floor(len / 536870912)
  local bit_len_lo = (len * 8) % 4294967296

  local pad_zeros = (55 - (len % 64)) % 64
  msg = msg .. "\128" .. string.rep("\0", pad_zeros) .. num_to_be32(bit_len_hi) .. num_to_be32(bit_len_lo)

  local h1, h2, h3, h4, h5, h6, h7, h8 =
    H0[1], H0[2], H0[3], H0[4], H0[5], H0[6], H0[7], H0[8]

  local W = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local b1, b2, b3, b4 = string.byte(msg, chunk + i * 4, chunk + i * 4 + 3)
      W[i + 1] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
    end
    for i = 17, 64 do
      local w15 = W[i - 15]
      local s0 = bxor(bxor(ror(w15, 7), ror(w15, 18)), rshift(w15, 3))
      local w2 = W[i - 2]
      local s1 = bxor(bxor(ror(w2, 17), ror(w2, 19)), rshift(w2, 10))
      W[i] = u32(u32(W[i - 16] + u32(s0)) + u32(W[i - 7] + u32(s1)))
    end

    local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
    for i = 1, 64 do
      local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local temp1 = u32(u32(h + u32(S1)) + u32(u32(ch) + u32(K[i] + W[i])))
      local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
      local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
      local temp2 = u32(u32(S0) + u32(maj))

      h = g
      g = f
      f = e
      e = u32(d + temp1)
      d = c
      c = b
      b = a
      a = u32(temp1 + temp2)
    end

    h1 = u32(h1 + a)
    h2 = u32(h2 + b)
    h3 = u32(h3 + c)
    h4 = u32(h4 + d)
    h5 = u32(h5 + e)
    h6 = u32(h6 + f)
    h7 = u32(h7 + g)
    h8 = u32(h8 + h)
  end

  return num_to_be32(h1) .. num_to_be32(h2) .. num_to_be32(h3) .. num_to_be32(h4)
      .. num_to_be32(h5) .. num_to_be32(h6) .. num_to_be32(h7) .. num_to_be32(h8)
end

function sha256.to_hex(raw)
  return (raw:gsub(".", function(c)
    return string.format("%02x", string.byte(c))
  end))
end

function sha256.from_hex(hex)
  return (hex:gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

function sha256.hex(msg)
  return sha256.to_hex(sha256.digest_raw(msg))
end

function sha256.hmac_raw(key, message)
  key = tostring(key or "")
  message = tostring(message or "")
  if #key > 64 then
    key = sha256.digest_raw(key)
  end
  if #key < 64 then
    key = key .. string.rep("\0", 64 - #key)
  end
  local o_key = {}
  local i_key = {}
  for i = 1, 64 do
    local kb = string.byte(key, i)
    o_key[i] = string.char(u32(bxor(kb, 0x5c)) % 256)
    i_key[i] = string.char(u32(bxor(kb, 0x36)) % 256)
  end
  local inner = sha256.digest_raw(table.concat(i_key) .. message)
  return sha256.digest_raw(table.concat(o_key) .. inner)
end

function sha256.hmac_hex(key, message)
  return sha256.to_hex(sha256.hmac_raw(key, message))
end

sha256.sha256_hex = sha256.hex
sha256.hmac_sha256_hex = sha256.hmac_hex

function sha256.constant_time_eq(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then
    return false
  end
  local diff = 0
  for i = 1, #a do
    diff = bor(diff, bxor(string.byte(a, i), string.byte(b, i)))
  end
  return u32(diff) == 0
end

return sha256
