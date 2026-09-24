local _, PK = ...

-- Profile export/import as one pasteable string. Pure Lua (no WoW APIs) so
-- it can be unit tested.
--
-- Format:  NLPT:<version>:<adler32 hex>:<base64 payload>
-- Payload: a small typed encoding (never loadstring'd, so an imported string
-- can't run code):
--   s<len>:<bytes>   string        n<number>;   number
--   T / F            boolean       { key value key value ... }   table
-- Only string/number keys and string/number/boolean/table values are allowed.
-- Base64 keeps the text free of "|", which WoW edit boxes treat as escapes.

local Serializer = {}
PK.Serializer = Serializer

local FORMAT_VERSION = 1
local MAX_DEPTH = 20

-- Encoding ------------------------------------------------------------------------

local function keySort(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return ta == "number"
	end
	return a < b
end

local function encodeValue(v, out, depth, seen)
	local t = type(v)
	if t == "string" then
		out[#out + 1] = "s" .. #v .. ":" .. v
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("cannot export NaN or infinite numbers")
		end
		out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
	elseif t == "boolean" then
		out[#out + 1] = v and "T" or "F"
	elseif t == "table" then
		if depth >= MAX_DEPTH then
			error("table nested too deeply")
		end
		if seen[v] then
			error("table contains a cycle")
		end
		seen[v] = true
		local keys = {}
		for k in pairs(v) do
			local kt = type(k)
			if kt ~= "string" and kt ~= "number" then
				error("unsupported key type: " .. kt)
			end
			keys[#keys + 1] = k
		end
		table.sort(keys, keySort)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			encodeValue(k, out, depth + 1, seen)
			encodeValue(v[k], out, depth + 1, seen)
		end
		out[#out + 1] = "}"
		seen[v] = nil
	else
		error("unsupported value type: " .. t)
	end
end

-- Decoding ------------------------------------------------------------------------

local decodeValue

local function decodeTable(s, pos, depth)
	if depth >= MAX_DEPTH then
		error("table nested too deeply")
	end
	local t = {}
	while true do
		local c = s:sub(pos, pos)
		if c == "}" then
			return t, pos + 1
		elseif c == "" then
			error("unexpected end of data")
		end
		local k
		k, pos = decodeValue(s, pos, depth + 1)
		if type(k) ~= "string" and type(k) ~= "number" then
			error("invalid key")
		end
		local v
		v, pos = decodeValue(s, pos, depth + 1)
		t[k] = v
	end
end

function decodeValue(s, pos, depth)
	local c = s:sub(pos, pos)
	if c == "s" then
		local len, rest = s:match("^(%d+):()", pos + 1)
		len = tonumber(len)
		if not len or rest + len - 1 > #s then
			error("bad string at " .. pos)
		end
		return s:sub(rest, rest + len - 1), rest + len
	elseif c == "n" then
		local num, rest = s:match("^([^;]+);()", pos + 1)
		local v = tonumber(num)
		if not v then
			error("bad number at " .. pos)
		end
		return v, rest
	elseif c == "T" then
		return true, pos + 1
	elseif c == "F" then
		return false, pos + 1
	elseif c == "{" then
		return decodeTable(s, pos + 1, depth)
	end
	error("unexpected '" .. c .. "' at " .. pos)
end

-- Checksum (Adler-32, arithmetic only; Lua 5.1 has no bit operators) -----------

function Serializer.Checksum(s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return string.format("%08x", b * 65536 + a)
end

-- Base64 ----------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for i = 1, 64 do
	DECODE[ALPHABET:byte(i)] = i - 1
end

function Serializer.Base64Encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local b1, b2, b3 = s:byte(i, i + 2)
		local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1)
			.. (b2 and ALPHABET:sub(c3 + 1, c3 + 1) or "=")
			.. (b3 and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

-- Returns the decoded string, or nil if s isn't valid base64.
function Serializer.Base64Decode(s)
	s = s:gsub("%s", "")
	if #s % 4 ~= 0 then
		return nil
	end
	local out = {}
	for i = 1, #s, 4 do
		local n, pad = 0, 0
		for j = 0, 3 do
			local byte = s:byte(i + j)
			local v = DECODE[byte]
			if byte == 61 then -- "="
				if i + 4 <= #s then
					return nil -- padding only allowed at the end
				end
				pad = pad + 1
				v = 0
			elseif not v then
				return nil
			end
			n = n * 64 + v
		end
		local b1 = math.floor(n / 65536) % 256
		local b2 = math.floor(n / 256) % 256
		local b3 = n % 256
		if pad == 0 then
			out[#out + 1] = string.char(b1, b2, b3)
		elseif pad == 1 then
			out[#out + 1] = string.char(b1, b2)
		elseif pad == 2 then
			out[#out + 1] = string.char(b1)
		else
			return nil
		end
	end
	return table.concat(out)
end

-- Public API ------------------------------------------------------------------------

-- Returns the export string, or nil and an error message.
function Serializer.Encode(tbl)
	local out = {}
	local ok, err = pcall(encodeValue, tbl, out, 0, {})
	if not ok then
		return nil, tostring(err)
	end
	local payload = table.concat(out)
	return "NLPT:" .. FORMAT_VERSION .. ":" .. Serializer.Checksum(payload) .. ":" .. Serializer.Base64Encode(payload)
end

-- Returns the decoded table, or nil and a user-readable error message.
function Serializer.Decode(str)
	if type(str) ~= "string" then
		return nil, "nothing to import"
	end
	str = str:gsub("%s", "")
	local version, checksum, body = str:match("^NLPT:(%d+):(%x+):(.+)$")
	if not version then
		return nil, "that isn't a Paladin Toolkit export string"
	end
	if tonumber(version) > FORMAT_VERSION then
		return nil, "that string is from a newer version of the addon"
	end
	local payload = Serializer.Base64Decode(body)
	if not payload then
		return nil, "the string is damaged (invalid characters)"
	end
	if Serializer.Checksum(payload) ~= checksum:lower() then
		return nil, "the string is incomplete or was changed (checksum mismatch)"
	end
	local ok, value, pos = pcall(decodeValue, payload, 1, 0)
	if not ok then
		return nil, "the string is damaged (" .. tostring(value) .. ")"
	end
	if pos ~= #payload + 1 then
		return nil, "the string is damaged (extra data)"
	end
	if type(value) ~= "table" then
		return nil, "the string doesn't contain a profile"
	end
	return value
end
