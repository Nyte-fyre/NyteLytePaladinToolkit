local _, PK = ...

-- Blessing Manager: PallyPower-style Blessing and Aura coordination.
--  * Assignments: which Blessing each paladin gives each class, and each
--    paladin's Aura (edited in the grid, UI/BlessingGrid.lua, /ptk bless).
--    You edit your own row; the group leader/assistants can edit any row.
--  * Sync with other paladins running the addon through addon messages
--    (Services/Comm.lua: out of combat, outside encounters, party/raid only).
--  * The buff button: a secure action button that casts your assigned
--    Blessing on the next group member missing it. One press = one cast;
--    the addon only picks the target and spell, and only out of combat
--    (secure attributes can't change in combat).
-- It never sends chat on its own; "Announce" in the grid is a manual button.

local B = PK.Blessings
local Comm = PK.Comm
local Roster = PK.Roster
local Theme = PK.Theme
local M = PK:RegisterModule("BlessingManager", {})
M.peers = {} -- [name] = { version, blessings = set, auras = set, seen }

local BUTTON_NAME = "NyteLytePaladinToolkitBuffButton"
local button, gridButton, countText, targetText, classIcon
local wasInGroup = false

local function settings()
	return PK.Config:GetModuleSettings("BlessingManager")
end

local function assignments()
	return PK.profile.blessing.assignments
end

local function me()
	return UnitName("player")
end

local function inGroup()
	return (IsInGroup and IsInGroup()) or false
end

-- Blessings and Auras this character knows (registry keys).
function M:KnownSets()
	local blessings, auras = {}, {}
	for key, r in pairs(PK.SpellRegistry.byKey) do
		if r.known then
			if r.category == "blessing" then
				blessings[key] = true
			elseif r.category == "greaterBlessing" and B.GREATER[key] then
				blessings[B.GREATER[key]] = true
			elseif r.category == "aura" then
				auras[key] = true
			end
		end
	end
	return blessings, auras
end

-- Paladins shown in the grid: you, group paladins, and paladins heard from.
function M:Paladins()
	local names, seen = {}, {}
	local function add(name)
		if name and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	add(me())
	for _, p in ipairs(Roster.paladins) do
		add(p.name)
	end
	table.sort(names, function(a, b)
		if a == me() then
			return true
		elseif b == me() then
			return false
		end
		return a < b
	end)
	return names
end

-- What a paladin knows: yours from the spellbook, others' from HELLO, else nil.
function M:KnownFor(name)
	if name == me() then
		return self:KnownSets()
	end
	local peer = self.peers[name]
	if peer then
		return peer.blessings, peer.auras
	end
	return nil, nil
end

-- Assignments with your own row filled in from a suggestion when you haven't
-- set one yet, so the buff button works out of the box.
function M:Effective()
	local a = assignments()
	if a[me()] then
		return a
	end
	local blessings, auras = self:KnownSets()
	local out = {}
	for k, v in pairs(a) do
		out[k] = v
	end
	out[me()] = B.Suggest({ { name = me(), blessings = blessings, auras = auras } })[me()]
	return out
end

function M:CanEdit(paladin)
	return paladin == me() or Roster:IsLeaderOrAssist(me())
end

-- Local edit of one cell (class = nil and aura given edits the Aura).
function M:SetAssignment(paladin, class, blessingKey, auraKey)
	if not self:CanEdit(paladin) then
		PK:Print("only the group leader or an assistant can change another paladin's Blessings.")
		return false
	end
	local cur = assignments()[paladin] or self:Effective()[paladin] or { classes = {} }
	local row = { classes = {}, aura = cur.aura, seq = (tonumber(cur.seq) or 0) + 1, ts = time() }
	for c, k in pairs(cur.classes or {}) do
		row.classes[c] = k
	end
	if class then
		row.classes[class] = blessingKey
	else
		row.aura = auraKey
	end
	B.ApplyRow(assignments(), paladin, row, { sender = me(), senderIsLeader = Roster:IsLeaderOrAssist(me()) })
	Comm:Send(B.EncodeRow(paladin, assignments()[paladin]), "ROW:" .. paladin)
	PK:Fire("PK_BLESSINGS_CHANGED")
	return true
end

-- Fills the grid from the auto-suggest layout. Rows you can't edit are left alone.
function M:ApplySuggestion()
	local list = {}
	for _, name in ipairs(self:Paladins()) do
		local blessings, auras = self:KnownFor(name)
		list[#list + 1] = { name = name, blessings = blessings, auras = auras }
	end
	local suggestion = B.Suggest(list)
	local leader = Roster:IsLeaderOrAssist(me())
	local changed = 0
	for name, sug in pairs(suggestion) do
		if name == me() or leader then
			local cur = assignments()[name]
			local row = { classes = sug.classes, aura = sug.aura, seq = (cur and tonumber(cur.seq) or 0) + 1, ts = time() }
			if B.ApplyRow(assignments(), name, row, { sender = me(), senderIsLeader = leader }) then
				Comm:Send(B.EncodeRow(name, assignments()[name]), "ROW:" .. name)
				changed = changed + 1
			end
		end
	end
	PK:Fire("PK_BLESSINGS_CHANGED")
	return changed
end

-- Posts the assignments to party/raid chat. Only ever called from a button click.
function M:Announce()
	local channel = Comm:Channel()
	if not channel then
		PK:Print("you're not in a group.")
		return
	end
	local send = PK.Compat.Resolve("C_ChatInfo.SendChatMessage") or _G.SendChatMessage
	if not send then
		return
	end
	local eff = self:Effective()
	for _, name in ipairs(self:Paladins()) do
		local row = eff[name]
		if row then
			local byBlessing = {}
			for _, class in ipairs(B.CLASSES) do
				local key = row.classes and row.classes[class]
				if key then
					byBlessing[key] = byBlessing[key] or {}
					table.insert(byBlessing[key], class:sub(1, 1) .. class:sub(2):lower())
				end
			end
			local parts = {}
			for _, key in ipairs(B.ASSIGNABLE) do
				if byBlessing[key] then
					local entry = PK.Spells.byKey[key]
					parts[#parts + 1] = entry.names[1]:gsub("Blessing of ", "") .. ": " .. table.concat(byBlessing[key], ", ")
				end
			end
			local auraEntry = row.aura and PK.Spells.byKey[row.aura]
			local line = name .. " - " .. table.concat(parts, "; ")
				.. (auraEntry and (" | Aura: " .. auraEntry.names[1]) or "")
			pcall(send, line:sub(1, 250), channel)
		end
	end
end

-- Sync ------------------------------------------------------------------------------------------

function M:SendHello(withRequest)
	local blessings, auras = self:KnownSets()
	Comm:Send(B.EncodeHello(PK.version, blessings, auras), "HELLO")
	local mine = assignments()[me()]
	if mine then
		Comm:Send(B.EncodeRow(me(), mine), "ROW:" .. me())
	end
	if withRequest then
		Comm:Send(B.EncodeRequest(), "REQ")
	end
end

function M:OnMessage(text, sender)
	local msg = B.Decode(text)
	if not msg then
		return
	end
	if msg.type == "HELLO" then
		local isNew = self.peers[sender] == nil
		self.peers[sender] = { version = msg.version, blessings = msg.blessings, auras = msg.auras, seen = time() }
		if isNew then
			self:SendHello(false) -- introduce ourselves back once
		end
		PK:Fire("PK_BLESSINGS_CHANGED")
	elseif msg.type == "ROW" then
		local ok = B.ApplyRow(assignments(), msg.paladin, msg,
			{ sender = sender, senderIsLeader = Roster:IsLeaderOrAssist(sender) })
		if ok then
			PK:Fire("PK_BLESSINGS_CHANGED")
		end
	elseif msg.type == "REQ" then
		-- Send every row we authored (our own, plus others' if we're the leader).
		for name, row in pairs(assignments()) do
			if row.by == me() then
				Comm:Send(B.EncodeRow(name, row), "ROW:" .. name)
			end
		end
	end
end

-- Buff button ------------------------------------------------------------------------------------

local function blessingSpell(key)
	local r = PK.SpellRegistry:Get(key)
	if r and r.known then
		return r.name, r.icon
	end
	return nil
end

-- Picks the next target out of combat and sets the secure attributes.
function M:UpdateButton()
	if not button then
		return
	end
	PK.CombatQueue:Run("BlessingButton", function()
		local shouldShow = M.enabled and (inGroup() or settings().showWhenSolo)
		if not shouldShow then
			button:Hide()
			return
		end
		button:Show()
		local eff = M:Effective()
		local members = {}
		for _, m in ipairs(Roster.members) do
			local key = B.AssignedFor(eff, me(), m.class)
			local spell = key and blessingSpell(key)
			if spell then
				members[#members + 1] = {
					unit = m.unit, name = m.name, class = m.class, buffs = m.buffs,
					usable = m.usable and Roster:InRange(spell, m.unit) ~= false,
				}
			end
		end
		local now = GetTime()
		local refreshSec = (PK.profile.blessing.refreshMinutes or 5) * 60
		local target, key, left, reason = B.PickTarget(eff, me(), members, now, refreshSec,
			settings().refreshLowest)
		local needing, names = B.CountNeeding(eff, me(), members, now, refreshSec)
		M.missingNames = names
		M.next = target and { name = target.name, class = target.class, key = key, left = left, reason = reason }
		if target then
			local spell, icon = blessingSpell(key)
			button:SetAttribute("type", "spell")
			button:SetAttribute("spell", spell)
			button:SetAttribute("unit", target.unit)
			button.icon:SetTexture(icon or Theme.ICON_BLESSING)
			button.icon:SetDesaturated(false)
		else
			button:SetAttribute("type", nil)
			button:SetAttribute("spell", nil)
			button:SetAttribute("unit", nil)
			button.icon:SetTexture(Theme.ICON_BLESSING)
			button.icon:SetDesaturated(true)
		end
		M:UpdateButtonText()
		countText:SetText(needing > 0 and Theme.Color("gold", needing .. " need" .. (needing == 1 and "s" or "") .. " it") or "")
	end)
end

local function formatLeft(sec)
	if not sec or sec == math.huge then
		return ""
	elseif sec >= 60 then
		return math.floor(sec / 60 + 0.5) .. "m"
	end
	return math.floor(sec) .. "s"
end

local function classColor(class, text)
	local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
	if c and c.colorStr then
		return "|c" .. c.colorStr .. text .. "|r"
	end
	return Theme.Color("light", text)
end

-- Name (class-colored) with a class icon, and what the next press does.
-- Safe in combat: only font strings and a plain texture change.
function M:UpdateButtonText()
	if not targetText then
		return
	end
	local n = self.next
	if not n then
		classIcon:Hide()
		targetText:SetText(Theme.Color("dim", "All blessed"))
		return
	end
	local coords = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[n.class]
	if coords then
		classIcon:SetTexCoord(unpack(coords))
		classIcon:Show()
	else
		classIcon:Hide()
	end
	local status
	if n.reason == "missing" then
		status = Theme.Color("alarm", "missing")
	elseif n.reason == "expiring" then
		status = Theme.Color("gold", formatLeft(n.left) .. " left")
	else
		status = Theme.Color("dim", "refresh (" .. formatLeft(n.left) .. ")")
	end
	targetText:SetText(classColor(n.class, n.name) .. " " .. status)
end

local function buildButton()
	PK.Frames:SetProtected("BlessingManager")
	local anchor = PK.Frames:GetAnchor("BlessingManager")
	local size = settings().buttonSize or 40
	anchor:SetSize(math.max(160, size + 120), size)

	button = CreateFrame("Button", BUTTON_NAME, anchor, "SecureActionButtonTemplate")
	button:SetSize(size, size)
	button:SetPoint("LEFT", anchor, "LEFT", 0, 0)
	-- One press = one cast: fire on key down or key up, never both.
	local down = false
	if C_CVar and C_CVar.GetCVarBool then
		local ok, v = pcall(C_CVar.GetCVarBool, "ActionButtonUseKeyDown")
		down = ok and v == true
	end
	button:RegisterForClicks(down and "AnyDown" or "AnyUp")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.icon:SetTexture(Theme.ICON_BLESSING)
	Theme.Edge(button, 1, 0.82, 0.25, 0.9, 1, "OVERLAY")
	local hl = button:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.9, 0.5, 0.25)

	classIcon = anchor:CreateTexture(nil, "ARTWORK")
	classIcon:SetSize(16, 16)
	classIcon:SetPoint("TOPLEFT", button, "TOPRIGHT", 8, -1)
	classIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
	classIcon:Hide()
	targetText = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	targetText:SetPoint("LEFT", classIcon, "RIGHT", 4, 0)
	countText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	countText:SetPoint("TOPLEFT", targetText, "BOTTOMLEFT", 0, -3)

	button:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Theme.Color("gold", "Buff next missing Blessing"))
		local n = M.next
		if n then
			local entry = PK.Spells.byKey[n.key]
			GameTooltip:AddLine("Next press: " .. (entry and entry.names[1] or "Blessing") .. " on " .. n.name
				.. (n.reason == "missing" and " (missing)" or (" (" .. formatLeft(n.left) .. " left)")), 1, 1, 1, true)
		else
			GameTooltip:AddLine("Nobody needs your Blessing right now.", 1, 1, 1, true)
		end
		GameTooltip:AddLine("One press = one cast. Missing Blessings come first, then ones about to run out"
			.. (settings().refreshLowest and ", then the lowest timer." or "."), 0.7, 0.7, 0.7, true)
		if M.missingNames and #M.missingNames > 0 then
			GameTooltip:AddLine("Need it: " .. table.concat(M.missingNames, ", "), 1, 0.82, 0.25, true)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	-- Small plain button that opens the assignment grid.
	gridButton = CreateFrame("Button", nil, anchor)
	gridButton:SetSize(16, 16)
	gridButton:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 8, 1)
	local gi = gridButton:CreateTexture(nil, "ARTWORK")
	gi:SetAllPoints()
	gi:SetTexture(Theme.ICON_GRID)
	gi:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	Theme.Edge(gridButton, 1, 0.82, 0.25, 0.9, 1, "OVERLAY")
	local ghl = gridButton:CreateTexture(nil, "HIGHLIGHT")
	ghl:SetAllPoints()
	ghl:SetColorTexture(1, 0.9, 0.5, 0.3)
	gridButton:SetScript("OnClick", function()
		if PK.BlessingGrid then
			PK.BlessingGrid:Toggle()
		end
	end)
	gridButton:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(Theme.Color("gold", "Blessing assignments"))
			GameTooltip:AddLine("Open the assignment grid (/ptk bless).", 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	gridButton:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	countText:ClearAllPoints()
	countText:SetPoint("LEFT", gridButton, "RIGHT", 4, 0)
end

-- Lifecycle ----------------------------------------------------------------------------------------

function M:OnEnable()
	if not button then
		PK.CombatQueue:Run("BlessingButtonBuild", function()
			buildButton()
			M:UpdateButton()
		end)
	end
	local function update()
		M:UpdateButton()
	end
	PK:On("PK_ROSTER_UPDATED", self, function()
		local grouped = inGroup()
		if grouped and not wasInGroup then
			M:SendHello(true)
		end
		wasInGroup = grouped
		update()
	end)
	PK:On("PK_BLESSINGS_CHANGED", self, update)
	PK:On("PK_SPELLS_UPDATED", self, update)
	PK:On("PK_SETTINGS_CHANGED", self, update)
	PK:On("PK_PROFILE_CHANGED", self, update)
	PK:On("PK_COMM_MESSAGE", self, function(_, _, text, sender)
		M:OnMessage(text, sender)
	end)
	wasInGroup = inGroup()
	if wasInGroup then
		self:SendHello(true)
	end
	update()
end

function M:OnDisable()
	for _, msg in ipairs({ "PK_ROSTER_UPDATED", "PK_BLESSINGS_CHANGED", "PK_SPELLS_UPDATED",
		"PK_SETTINGS_CHANGED", "PK_PROFILE_CHANGED", "PK_COMM_MESSAGE" }) do
		PK:Off(msg, self)
	end
	if button then
		PK.CombatQueue:Run("BlessingButton", function()
			button:Hide()
		end)
	end
	if PK.BlessingGrid then
		PK.BlessingGrid:Hide()
	end
end

function M:OnSpecChanged()
	self:UpdateButton()
end

PK:RegisterCommand("bless", function()
	if PK.BlessingGrid then
		PK.BlessingGrid:Toggle()
	end
end, "open the Blessing assignment grid")

-- Keybinding (Bindings.xml)
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Buff next missing Blessing"
BINDING_NAME_NLPT_TOGGLE_GRID = "Open Blessing assignment grid"
