local _, PK = ...

-- Every version-sensitive API call goes through here, so a client change
-- is fixed in one file. Each function tries the modern (C_*) API first,
-- falls back to the legacy global if it still exists, and never throws.

local Compat = {}
PK.Compat = Compat

-- Looks up "C_Spell.GetSpellInfo" style paths without erroring.
function Compat.Resolve(path)
	local cur = _G
	for part in path:gmatch("[^.]+") do
		if type(cur) ~= "table" then
			return nil
		end
		cur = cur[part]
		if cur == nil then
			return nil
		end
	end
	return cur
end

-- Secret values ----------------------------------------------------------------
local issecretvalue = _G.issecretvalue

function Compat.HasSecretValues()
	return issecretvalue ~= nil
end

-- True if v must not be compared, used in arithmetic, or branched on.
-- If the check itself fails, assume secret.
function Compat.IsSecret(v)
	if not issecretvalue then
		return false
	end
	local ok, r = pcall(issecretvalue, v)
	if not ok then
		return true
	end
	return r == true
end

-- Safe, storable description of any value: plain numbers, strings and
-- booleans pass through; secret values and objects become a "<...>" tag.
-- Never returns a secret value, so the result is safe to save or print.
function Compat.Describe(v)
	if Compat.IsSecret(v) then
		local ok, t = pcall(type, v)
		return "<secret " .. (ok and t or "?") .. ">"
	end
	local t = type(v)
	if t == "nil" then
		return "nil"
	elseif t == "number" or t == "boolean" then
		return v
	elseif t == "string" then
		if #v > 200 then
			return v:sub(1, 200) .. "..."
		end
		return v
	end
	return "<" .. t .. ">"
end

-- Tries arithmetic on v. Catches "secret" numbers even where the client has
-- no issecretvalue. Returns "ok", "error: ..." or "not a number".
function Compat.ArithmeticCheck(v)
	if type(v) ~= "number" then
		return "not a number"
	end
	local ok, err = pcall(function()
		return v + 0
	end)
	return ok and "ok" or ("error: " .. tostring(err))
end

-- Addon metadata ---------------------------------------------------------------
function Compat.GetAddOnMetadata(addon, field)
	local fn = Compat.Resolve("C_AddOns.GetAddOnMetadata") or _G.GetAddOnMetadata
	if not fn then
		return nil
	end
	local ok, v = pcall(fn, addon, field)
	return ok and v or nil
end

-- Spells -----------------------------------------------------------------------

-- Returns { name, spellID, iconID } or nil. Accepts a spell ID or name.
function Compat.GetSpellInfo(spell)
	local modern = Compat.Resolve("C_Spell.GetSpellInfo")
	if modern then
		local ok, info = pcall(modern, spell)
		if ok and type(info) == "table" then
			return info
		end
		return nil
	end
	local legacy = _G.GetSpellInfo
	if legacy then
		local ok, name, _, icon, _, _, _, id = pcall(legacy, spell)
		if ok and name then
			return { name = name, spellID = id, iconID = icon }
		end
	end
	return nil
end

-- Is the spell learned by the player? nil if no API could answer.
function Compat.IsSpellKnown(spellID)
	local candidates = {
		_G.IsPlayerSpell,
		Compat.Resolve("C_SpellBook.IsSpellKnown"),
		_G.IsSpellKnown,
	}
	for _, fn in ipairs(candidates) do
		local ok, r = pcall(fn, spellID)
		if ok and r ~= nil and not Compat.IsSecret(r) then
			return r and true or false
		end
	end
	return nil
end

function Compat.GetSpellName(spellID)
	local fn = Compat.Resolve("C_Spell.GetSpellName")
	if fn then
		local ok, name = pcall(fn, spellID)
		return ok and name or nil
	end
	local info = Compat.GetSpellInfo(spellID)
	return info and info.name
end

function Compat.GetSpellTexture(spellID)
	local fn = Compat.Resolve("C_Spell.GetSpellTexture")
	if fn and spellID then
		local ok, tex = pcall(fn, spellID)
		return ok and tex or nil
	end
	return nil
end

-- Talent points spent per tree: { holy = n, prot = n, ret = n }, or nil and
-- a reason. Forever's talents live in C_Traits; how its three trees map to
-- trait nodes is not known yet (needs a probe from a level 10+ character with
-- points spent), so this reports "unknown" rather than guessing.
function Compat.GetTalentPointsByTree()
	return nil, "talent tree mapping not verified yet"
end

-- Adds the spells inside a spellbook flyout (Forever groups Blessings and
-- Auras into flyouts) to list.
local function addFlyoutSpells(list, flyoutID, skillLine)
	local info, slotInfo = _G.GetFlyoutInfo, _G.GetFlyoutSlotInfo
	if not (info and slotInfo and flyoutID) then
		return
	end
	local ok, flyoutName, _, numSlots = pcall(info, flyoutID)
	if not ok or type(numSlots) ~= "number" then
		return
	end
	for slot = 1, numSlots do
		local ok2, spellID, _, isKnown, spellName = pcall(slotInfo, flyoutID, slot)
		if ok2 and spellID then
			list[#list + 1] = {
				name = spellName or Compat.GetSpellName(spellID),
				spellID = spellID,
				itemType = isKnown and "Spell" or "FutureSpell",
				flyout = flyoutName,
				skillLine = skillLine,
			}
		end
	end
end

-- Lists every spellbook entry for the player, including not-yet-learned
-- ("future") spells and the contents of flyouts. Returns list, method, err.
-- Entry: { name, spellID, subName, itemType, isPassive, skillLine, flyout }.
function Compat.ScanSpellbook()
	local list = {}
	local C = _G.C_SpellBook
	if C and C.GetNumSpellBookSkillLines and C.GetSpellBookSkillLineInfo and C.GetSpellBookItemInfo then
		local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
		local typeNames = {}
		if Enum and Enum.SpellBookItemType then
			for k, v in pairs(Enum.SpellBookItemType) do
				typeNames[v] = k
			end
		end
		local ok, err = pcall(function()
			for line = 1, C.GetNumSpellBookSkillLines() do
				local info = C.GetSpellBookSkillLineInfo(line)
				if info and info.numSpellBookItems then
					local offset = info.itemIndexOffset or 0
					for i = offset + 1, offset + info.numSpellBookItems do
						local item = C.GetSpellBookItemInfo(i, bank)
						if item then
							list[#list + 1] = {
								name = item.name,
								spellID = item.spellID or item.actionID,
								subName = item.subName ~= "" and item.subName or nil,
								itemType = typeNames[item.itemType] or item.itemType,
								isPassive = item.isPassive,
								isOffSpec = item.isOffSpec,
								skillLine = info.name,
							}
							if list[#list].itemType == "Flyout" then
								addFlyoutSpells(list, item.actionID, info.name)
							end
						end
					end
				end
			end
		end)
		return list, "C_SpellBook", (not ok) and tostring(err) or nil
	end
	if _G.GetNumSpellTabs and _G.GetSpellTabInfo and _G.GetSpellBookItemName then
		local ok, err = pcall(function()
			for tab = 1, GetNumSpellTabs() do
				local tabName, _, offset, num = GetSpellTabInfo(tab)
				for i = offset + 1, offset + num do
					local name, subName, id = GetSpellBookItemName(i, "spell")
					if name then
						list[#list + 1] = { name = name, subName = subName, spellID = id, skillLine = tabName }
					end
				end
			end
		end)
		return list, "legacy", (not ok) and tostring(err) or nil
	end
	return list, "none", "no spellbook API found"
end

-- Cooldowns --------------------------------------------------------------------

-- Raw cooldown info table (fields may be secret in combat) or nil.
function Compat.GetSpellCooldown(spellID)
	local modern = Compat.Resolve("C_Spell.GetSpellCooldown")
	if modern then
		local ok, info = pcall(modern, spellID)
		return ok and info or nil
	end
	local legacy = _G.GetSpellCooldown
	if legacy then
		local ok, start, duration, enabled, modRate = pcall(legacy, spellID)
		if ok then
			return { startTime = start, duration = duration, isEnabled = enabled, modRate = modRate }
		end
	end
	return nil
end

-- Duration object for display-only cooldown swipes, or nil. ignoreGCD asks
-- the client to leave out the global cooldown (ignored if unsupported).
function Compat.GetSpellCooldownDuration(spellID, ignoreGCD)
	local fn = Compat.Resolve("C_Spell.GetSpellCooldownDuration")
	if not fn then
		return nil
	end
	local ok, d = pcall(fn, spellID, ignoreGCD)
	if not ok then
		ok, d = pcall(fn, spellID)
	end
	return ok and d or nil
end

-- usable, noMana for a spell (either may be nil if unreadable).
function Compat.IsSpellUsable(spellID)
	local fn = Compat.Resolve("C_Spell.IsSpellUsable") or _G.IsUsableSpell
	if not fn then
		return nil, nil
	end
	local ok, usable, noMana = pcall(fn, spellID)
	if not ok then
		return nil, nil
	end
	return PK.Secrets.SafeBool(usable), PK.Secrets.SafeBool(noMana)
end

-- The active Paladin aura via the stance bar (readable in combat on
-- Forever, unlike aura queries). Returns spellID, icon or nil.
function Compat.GetActiveStanceSpell()
	local getForm, getInfo = _G.GetShapeshiftForm, _G.GetShapeshiftFormInfo
	if not (getForm and getInfo) then
		return nil
	end
	local ok, index = pcall(getForm)
	if not ok or Compat.IsSecret(index) or type(index) ~= "number" or index < 1 then
		return nil
	end
	local ok2, icon, active, _, spellID = pcall(getInfo, index)
	if not ok2 or Compat.IsSecret(spellID) or Compat.IsSecret(active) or not active then
		return nil
	end
	return spellID, icon
end

function Compat.PlaySound(kitName, fallbackID)
	local id = (_G.SOUNDKIT and _G.SOUNDKIT[kitName]) or fallbackID
	if id and _G.PlaySound then
		pcall(_G.PlaySound, id, "Master")
	end
end

-- Auras ------------------------------------------------------------------------

-- Returns a list of raw aura data tables for unit (fields may be secret).
function Compat.GetAuras(unit, filter)
	local list = {}
	local byIndex = Compat.Resolve("C_UnitAuras.GetAuraDataByIndex")
	if byIndex then
		for i = 1, 80 do
			local ok, aura = pcall(byIndex, unit, i, filter)
			if not ok or Compat.IsSecret(aura) or type(aura) ~= "table" then
				break
			end
			list[#list + 1] = aura
		end
		return list, "C_UnitAuras"
	end
	local legacy = _G.UnitAura
	if legacy then
		for i = 1, 80 do
			local ok, name, icon, count, _, duration, expiration, source, _, _, spellId = pcall(legacy, unit, i, filter)
			if not ok or not name then
				break
			end
			list[#list + 1] = {
				name = name, icon = icon, applications = count, duration = duration,
				expirationTime = expiration, sourceUnit = source, spellId = spellId,
			}
		end
		return list, "UnitAura"
	end
	return list, "none"
end

function Compat.InCombat()
	return InCombatLockdown and InCombatLockdown() or false
end
