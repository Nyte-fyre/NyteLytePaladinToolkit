local _, PK = ...

-- Settings panel (M1 skeleton): spec mode, per-spec module toggles, frame
-- lock/reset, and profile export/import/reset. Registered in the game's
-- Settings window (Options > AddOns) when the Settings API exists, otherwise
-- shown as a standalone window. Opened with /ptk.

local Presets = PK.Presets
local SP = PK.SpecProfile
local S = {}
PK.Settings = S

local SPECS = { "holy", "prot", "ret" }
local MODE_BUTTONS = { "auto", "holy", "prot", "ret" }

local panel, category, fallbackWindow
local modeButtons, checkboxes, optionBoxes = {}, {}, {}

local function ms(module)
	return PK.Config:GetModuleSettings(module)
end

-- Module options shown as checkboxes: { label, get(), set(value) }.
local OPTIONS = {
	{ "Sound alerts", function()
		return PK.profile.alerts.sound
	end, function(v)
		PK.profile.alerts.sound = v
	end },
	{ "Buff Sentinel: also show buffs that are fine", function()
		return ms("BuffSentinel").showAll
	end, function(v)
		ms("BuffSentinel").showAll = v
	end },
	{ "Righteous Fury warning as Protection", function()
		return ms("BuffSentinel").rfSpecs.prot
	end, function(v)
		ms("BuffSentinel").rfSpecs.prot = v
	end },
	{ "Righteous Fury warning as Holy/Retribution", function()
		return ms("BuffSentinel").rfSpecs.holy
	end, function(v)
		ms("BuffSentinel").rfSpecs.holy = v
		ms("BuffSentinel").rfSpecs.ret = v
	end },
	{ "Seal Tracker: time bar", function()
		return ms("SealTracker").showBar
	end, function(v)
		ms("SealTracker").showBar = v
	end },
	{ "Seal Tracker: Twist of Light Echo (Ret)", function()
		return ms("SealTracker").showEcho
	end, function(v)
		ms("SealTracker").showEcho = v
	end },
	{ "Tank Kit: big Righteous Fury warning", function()
		return ms("TankKit").rfWarning
	end, function(v)
		ms("TankKit").rfWarning = v
	end },
	{ "Tank Kit: Righteous Fury sound (zone-in, ready check)", function()
		return ms("TankKit").rfSound
	end, function(v)
		ms("TankKit").rfSound = v
	end },
	{ "Cooldown HUD: show unlearned spells", function()
		return ms("CooldownHUD").showUnknown
	end, function(v)
		ms("CooldownHUD").showUnknown = v
	end },
	{ "Cooldown HUD: vertical", function()
		return ms("CooldownHUD").direction == "DOWN"
	end, function(v)
		ms("CooldownHUD").direction = v and "DOWN" or "RIGHT"
	end },
}
local statusText, lockButton, profileText

local function header(parent, text, y, x, width)
	return PK.Theme.Header(parent, text, x or 16, y, width or 290)
end

local function button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function exportProfile()
	local str, err = PK.Config:ExportProfile()
	if not str then
		PK:Print("export failed: " .. tostring(err))
		return
	end
	PK.CopyWindow:Show(PK.displayName .. " - export profile \"" .. PK.Config:GetProfileName() .. "\"", str)
end

local function importProfile()
	PK.CopyWindow:ShowInput(PK.displayName .. " - import profile",
		"Paste an export string (Ctrl+V), then click Import. This replaces your current profile.",
		function(text)
			local ok, err = PK.Config:ImportProfile(text)
			if ok then
				PK:Print("profile imported into \"" .. PK.Config:GetProfileName() .. "\".")
			else
				PK:Print("import failed: " .. tostring(err))
			end
			return ok
		end)
end

-- Adding a key is fine; never reassign the StaticPopupDialogs global itself (taint).
local resetDialog = {
	text = "Reset all Paladin Toolkit settings in this profile to defaults?",
	button1 = "Reset",
	button2 = "Cancel",
	OnAccept = function()
		PK.Config:ResetProfile()
		PK:Print("profile reset to defaults.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}
if StaticPopupDialogs then
	StaticPopupDialogs.NLPT_RESET_PROFILE = resetDialog
end

local function Build()
	panel = CreateFrame("Frame")
	panel:SetSize(620, 680)
	panel.name = PK.displayName

	PK.Theme.AddGlow(panel, 80)
	local title = PK.Theme.Title(panel, PK.displayName, 16, -12)
	local version = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("LEFT", title, "RIGHT", 8, 0)
	version:SetText("v" .. PK.version)

	-- Spec mode
	header(panel, "Spec", -52)
	for i, mode in ipairs(MODE_BUTTONS) do
		local b = button(panel, SP.LABELS[mode], 110, function()
			SP:SetMode(mode)
		end)
		b:SetPoint("TOPLEFT", 16 + (i - 1) * 116, -72)
		modeButtons[mode] = b
	end
	statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", 16, -102)
	statusText:SetWidth(580)
	statusText:SetJustifyH("LEFT")

	-- Module matrix
	header(panel, "Modules per spec", -132, 16, 590)
	for i, spec in ipairs(SPECS) do
		local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", 300 + (i - 1) * 90, -152)
		fs:SetWidth(80)
		fs:SetText(SP.LABELS[spec])
	end
	for row, module in ipairs(Presets.MODULES) do
		local y = -170 - (row - 1) * 28
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 24, y - 6)
		label.module = module
		checkboxes[module] = { label = label }
		for i, spec in ipairs(SPECS) do
			local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
			cb:SetPoint("TOPLEFT", 318 + (i - 1) * 90, y)
			cb:SetScript("OnClick", function(self)
				PK.Config:SetModuleEnabled(module, spec, self:GetChecked())
			end)
			checkboxes[module][spec] = cb
		end
	end

	-- Frames
	local framesY = -170 - #Presets.MODULES * 28 - 16
	header(panel, "Frames", framesY)
	lockButton = button(panel, "Unlock frames", 150, function()
		PK.Frames:ToggleLock()
	end)
	lockButton:SetPoint("TOPLEFT", 16, framesY - 20)
	local reset = button(panel, "Reset positions", 150, function()
		PK.Frames:ResetPositions()
	end)
	reset:SetPoint("LEFT", lockButton, "RIGHT", 8, 0)

	-- Module options (right column)
	local optX = 340
	header(panel, "Options", framesY, optX, 270)
	for i, opt in ipairs(OPTIONS) do
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", optX - 4, framesY - 16 - (i - 1) * 24)
		cb:SetSize(24, 24)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		label:SetText(opt[1])
		cb:SetScript("OnClick", function(self)
			opt[3](self:GetChecked() and true or false)
			PK:Fire("PK_SETTINGS_CHANGED")
		end)
		optionBoxes[i] = cb
	end
	local cdNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cdNote:SetPoint("TOPLEFT", optX, framesY - 24 - #OPTIONS * 24)
	cdNote:SetWidth(270)
	cdNote:SetJustifyH("LEFT")
	cdNote:SetText("Edit this spec's cooldown bar with /ptk cd (list, add, remove, reset).")

	-- Profile
	local profileY = framesY - 64
	header(panel, "Profile", profileY)
	profileText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profileText:SetPoint("TOPLEFT", 16, profileY - 20)
	local export = button(panel, "Export", 100, exportProfile)
	export:SetPoint("TOPLEFT", 16, profileY - 40)
	local import = button(panel, "Import", 100, importProfile)
	import:SetPoint("LEFT", export, "RIGHT", 8, 0)
	local resetProfile = button(panel, "Reset profile", 208, function()
		if StaticPopup_Show then
			StaticPopup_Show("NLPT_RESET_PROFILE")
		end
	end)
	resetProfile:SetPoint("TOPLEFT", export, "BOTTOMLEFT", 0, -6)
	local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 16, profileY - 104)
	note:SetWidth(310)
	note:SetJustifyH("LEFT")
	note:SetText("Export your profile now and then: the Forever beta has a reported bug where saved settings "
		.. "can reset on a fresh client start. Type /ptk help for all commands.")

	panel:SetScript("OnShow", function()
		S:Refresh()
	end)
end

function S:Refresh()
	if not panel or not PK.profile then
		return
	end
	local d = SP:GetDecision()
	local mode = PK.profile.specMode
	for m, b in pairs(modeButtons) do
		if m == mode then
			b:LockHighlight()
		else
			b:UnlockHighlight()
		end
	end
	if d then
		statusText:SetText(string.format("Active: |cffffffff%s|r   (Auto %s)", SP.LABELS[d.spec],
			SP:DescribeDetection(d.detected)))
	else
		statusText:SetText("")
	end
	for _, module in ipairs(Presets.MODULES) do
		local row = checkboxes[module]
		local built = PK.modules[module] ~= nil
		row.label:SetText((Presets.MODULE_LABELS[module] or module) .. (built and "" or " |cff808080(coming soon)|r"))
		for _, spec in ipairs(SPECS) do
			row[spec]:SetChecked(PK.Config:IsModuleEnabled(module, spec))
		end
	end
	for i, opt in ipairs(OPTIONS) do
		optionBoxes[i]:SetChecked(opt[2]() and true or false)
	end
	lockButton:SetText(PK.profile.locked and "Unlock frames" or "Lock frames")
	profileText:SetText("Current profile: |cffffffff" .. tostring(PK.Config:GetProfileName()) .. "|r")
end

local function register()
	Build()
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, PK.displayName)
		if ok and cat then
			category = cat
			pcall(Settings.RegisterAddOnCategory, category)
			return
		end
	end
	-- No Settings API: host the panel in a standalone window.
	fallbackWindow = PK.Theme.CreateWindow("NyteLytePaladinToolkitSettings", PK.displayName, 650, 720)
	fallbackWindow.titleText:Hide() -- the panel draws its own title
	fallbackWindow.titleIcon:Hide()
	panel:SetParent(fallbackWindow)
	panel:SetPoint("TOPLEFT", 8, -8)
end

function S:Open()
	if not panel then
		return
	end
	if PK.Compat.InCombat() then
		PK:Print("settings will open when combat ends.")
		PK.CombatQueue:Run("openSettings", function()
			S:Open()
		end)
		return
	end
	if category then
		local id = category.GetID and category:GetID() or category.ID
		local ok = pcall(Settings.OpenToCategory, id)
		if not ok then
			PK:Print("couldn't open the settings window; use Options > AddOns > " .. PK.displayName .. ".")
		end
	elseif fallbackWindow then
		fallbackWindow:Show()
		S:Refresh()
	end
end

local function refresh()
	S:Refresh()
end
PK:On("PK_READY", S, register)
PK:On("PK_SPEC_EVALUATED", S, refresh)
PK:On("PK_PROFILE_CHANGED", S, refresh)
PK:On("PK_MODULES_CHANGED", S, refresh)
PK:On("PK_LOCK_CHANGED", S, refresh)
PK:On("PK_SETTINGS_CHANGED", S, refresh)

PK:RegisterCommand("config", function()
	S:Open()
end, "open settings (same as /ptk)")
PK:RegisterCommand("export", exportProfile, "export your profile as a text string")
PK:RegisterCommand("import", importProfile, "import a profile string")
