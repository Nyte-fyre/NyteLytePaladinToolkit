local _, PK = ...

-- Secret-value-safe reads. Every read returns one of three states so callers
-- must handle all of them:
--   Secrets.VALUE        the value is readable and safe to compare/do math on
--   Secrets.SECRET       the API answered, but with a secret value (display only)
--   Secrets.UNAVAILABLE  the API is missing, errored, or returned nothing
-- Never branch on, compare, or do arithmetic with a value unless its state is VALUE.

local Compat = PK.Compat
local Secrets = {
	VALUE = "value",
	SECRET = "secret",
	UNAVAILABLE = "unavailable",
}
PK.Secrets = Secrets

-- Classifies a single value.
function Secrets.State(v)
	if Compat.IsSecret(v) then
		return Secrets.SECRET
	end
	if v == nil then
		return Secrets.UNAVAILABLE
	end
	return Secrets.VALUE
end

-- Calls fn(...) safely and classifies its first return value.
-- Returns state, value (value is only meaningful for VALUE and SECRET).
function Secrets.Read(fn, ...)
	if type(fn) ~= "function" then
		return Secrets.UNAVAILABLE, nil
	end
	local ok, v = pcall(fn, ...)
	if not ok then
		return Secrets.UNAVAILABLE, nil
	end
	return Secrets.State(v), v
end

-- Reads t[key] from an API result table. Returns state, value.
function Secrets.Field(t, key)
	if type(t) ~= "table" or Compat.IsSecret(t) then
		return Secrets.UNAVAILABLE, nil
	end
	local ok, v = pcall(function()
		return t[key]
	end)
	if not ok then
		return Secrets.UNAVAILABLE, nil
	end
	return Secrets.State(v), v
end

-- The value if it's a readable number, otherwise nil.
function Secrets.SafeNumber(v)
	if Compat.IsSecret(v) or type(v) ~= "number" then
		return nil
	end
	return v
end

-- The value if it's a readable boolean, otherwise nil.
function Secrets.SafeBool(v)
	if Compat.IsSecret(v) or type(v) ~= "boolean" then
		return nil
	end
	return v
end

-- The value if it's a readable string, otherwise nil.
function Secrets.SafeString(v)
	if Compat.IsSecret(v) or type(v) ~= "string" then
		return nil
	end
	return v
end
