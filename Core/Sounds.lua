local _, PK = ...

-- Warning sounds. Each warning plays the sound picked for it in the
-- settings (Sounds section): one of the game's own sounds, or one of your
-- own files. Own files go in Interface/AddOns/NyteLytePaladinToolkit_Sounds/
-- named custom1 ... custom5 (.ogg or .mp3). That folder is separate so
-- addon updates never delete it. WoW only notices new files after a full
-- game restart (not /reload).
-- Whether a warning makes a sound at all is still its own option (and the
-- master "Sound alerts" switch); "None" silences just that one.

local L = PK.L
local Sounds = {}
PK.Sounds = Sounds

-- { key, label, SOUNDKIT name, fallback sound kit ID }
Sounds.LIST = {
	{ key = "NONE", label = L["None"] },
	{ key = "RAID_WARNING", label = L["Raid warning"], kit = "RAID_WARNING", id = 8959 },
	{ key = "READY_CHECK", label = L["Ready check"], kit = "READY_CHECK", id = 8960 },
	{ key = "ALARM", label = L["Alarm clock"], kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
	{ key = "BOSS_WHISPER", label = L["Boss warning"], kit = "UI_RAID_BOSS_WHISPER_WARNING", id = 37666 },
	{ key = "WHISPER", label = L["Whisper"], kit = "TELL_MESSAGE", id = 3081 },
	{ key = "LEVEL_UP", label = L["Level up"], kit = "LEVELUP", id = 888 },
	{ key = "MAP_PING", label = L["Map ping"], kit = "MAP_PING", id = 3175 },
	{ key = "INVITE", label = L["Invite"], kit = "IG_PLAYER_INVITE", id = 880 },
	{ key = "QUEUE_POP", label = L["Queue pop"], kit = "PVP_THROUGH_QUEUE", id = 8459 },
}
Sounds.CUSTOM_FOLDER = "Interface\\AddOns\\NyteLytePaladinToolkit_Sounds\\"
for i = 1, 5 do
	table.insert(Sounds.LIST, { key = "CUSTOM" .. i, label = L["Custom %d"]:format(i), file = "custom" .. i })
end
Sounds.byKey = {}
for i, s in ipairs(Sounds.LIST) do
	s.index = i
	Sounds.byKey[s.key] = s
end

-- The warnings that make a sound, in settings order.
Sounds.EVENTS = {
	{ key = "missing", label = L["Missing buff"] },
	{ key = "readyCheck", label = L["Ready check problem"] },
	{ key = "seal", label = L["Seal running out"] },
	{ key = "rf", label = L["Righteous Fury missing"] },
	{ key = "rebuff", label = L["After-combat rebuff"] },
}
Sounds.DEFAULT = "RAID_WARNING"

function Sounds:Get(event)
	local chosen = PK.profile and PK.profile.alerts and PK.profile.alerts.sounds
	local key = chosen and chosen[event]
	return self.byKey[key] or self.byKey[self.DEFAULT]
end

function Sounds:Set(event, key)
	if not (PK.profile and self.byKey[key]) then
		return
	end
	PK.profile.alerts.sounds = PK.profile.alerts.sounds or {}
	PK.profile.alerts.sounds[event] = key
	PK:Fire("PK_SETTINGS_CHANGED")
end

-- Moves the event's sound one step through the list (-1 goes back).
function Sounds:Cycle(event, step)
	local i = self:Get(event).index + (step or 1)
	if i > #self.LIST then
		i = 1
	elseif i < 1 then
		i = #self.LIST
	end
	self:Set(event, self.LIST[i].key)
	return self.LIST[i]
end

-- Returns false when a custom file isn't there (or can't play).
function Sounds:PlaySound(s)
	if not s then
		return true
	end
	if s.kit then
		PK.Compat.PlaySound(s.kit, s.id)
		return true
	end
	if s.file and _G.PlaySoundFile then
		for _, ext in ipairs({ ".ogg", ".mp3" }) do
			local ok, willPlay = pcall(_G.PlaySoundFile, self.CUSTOM_FOLDER .. s.file .. ext, "Master")
			if ok and willPlay then
				return true
			end
		end
		return false
	end
	return true
end

-- Plays a sound from the settings; explains where a missing file goes.
function Sounds:Preview(s)
	if not self:PlaySound(s) then
		PK:Print(L["%s: no file found. Put %s.ogg or %s.mp3 in Interface\\AddOns\\NyteLytePaladinToolkit_Sounds and restart the game."]
			:format(s.label, s.file, s.file))
	end
end

-- Plays the sound picked for this warning ("None" plays nothing).
function Sounds:Play(event)
	self:PlaySound(self:Get(event))
end
