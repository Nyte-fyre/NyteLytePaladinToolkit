local _, PK = ...

-- Decides the effective spec from the spec mode and whatever detection data
-- is available. Pure Lua (no WoW APIs) so it can be unit tested.

local SpecDecision = {}
PK.SpecDecision = SpecDecision

SpecDecision.SPECS = { "holy", "prot", "ret" }
SpecDecision.MODES = { "auto", "holy", "prot", "ret" }
SpecDecision.FALLBACK = "holy"

local VALID = { holy = true, prot = true, ret = true }

function SpecDecision.IsSpec(s)
	return VALID[s] == true
end

-- Returns the spec with the strictly highest count and that count, or nil if
-- nothing is above zero or the top two are tied.
local function pickHighest(counts)
	if type(counts) ~= "table" then
		return nil
	end
	local best, bestVal, second = nil, 0, 0
	for _, spec in ipairs(SpecDecision.SPECS) do
		local v = tonumber(counts[spec]) or 0
		if v > bestVal then
			best, second, bestVal = spec, bestVal, v
		elseif v > second then
			second = v
		end
	end
	if not best or bestVal == second then
		return nil
	end
	return best, bestVal, second
end

-- Auto detection only (ignores the mode).
-- input.talentPoints / input.knownSpecSpells: { holy = n, prot = n, ret = n }
-- Returns { spec, confidence = "high"|"low"|"none", method }.
function SpecDecision.Detect(input)
	input = input or {}
	local spec, top, second = pickHighest(input.talentPoints)
	if spec then
		return { spec = spec, confidence = (top - second >= 3) and "high" or "low", method = "talent points" }
	end
	spec = pickHighest(input.knownSpecSpells)
	if spec then
		return { spec = spec, confidence = "low", method = "known spells" }
	end
	return { spec = SpecDecision.FALLBACK, confidence = "none", method = "could not detect" }
end

-- Full decision. Returns { spec, mode, confidence, method, detected }, where
-- detected is the auto-detection result (shown in settings even in manual mode).
function SpecDecision.Decide(mode, input)
	local detected = SpecDecision.Detect(input)
	if VALID[mode] then
		return { spec = mode, mode = mode, confidence = "manual", method = "chosen by you", detected = detected }
	end
	return {
		spec = detected.spec,
		mode = "auto",
		confidence = detected.confidence,
		method = detected.method,
		detected = detected,
	}
end

-- Forever has one retail-style talent tree with the three Classic trees side
-- by side (probe at level 10, 2026-09-24): Holy nodes sit at x ~1000-2800,
-- Protection at ~5000-6800, Retribution at ~9000-10900. Returns the tree for
-- a node's x position, or nil.
SpecDecision.TREE_X_BOUNDS = { holy = 4000, prot = 8000 }

function SpecDecision.SpecForTalentX(x)
	if type(x) ~= "number" then
		return nil
	end
	if x < SpecDecision.TREE_X_BOUNDS.holy then
		return "holy"
	elseif x < SpecDecision.TREE_X_BOUNDS.prot then
		return "prot"
	end
	return "ret"
end

-- Next mode in the cycle auto -> holy -> prot -> ret -> auto.
function SpecDecision.NextMode(mode)
	for i, m in ipairs(SpecDecision.MODES) do
		if m == mode then
			return SpecDecision.MODES[i % #SpecDecision.MODES + 1]
		end
	end
	return "auto"
end
