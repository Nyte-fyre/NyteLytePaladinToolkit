-- M4 flows (Blessing Manager, sync, buff button, grid), run after m3_flows.lua.
local P = NyteLytePaladinToolkit
local BM = P.modules.BlessingManager
local slash = function(msg)
	SlashCmdList.NYTELYTEPALADINTOOLKIT(msg)
end
local function settle()
	for _ = 1, 3 do
		MOCK.runTimers()
	end
end
local function flush()
	MOCK.tick(40)
end
local function sentTexts()
	local out = {}
	for _, m in ipairs(MOCK.sent) do
		if m.prefix == "NLPT" then
			out[#out + 1] = m.channel .. " " .. m.text
		end
	end
	return out
end
local function lastSentStarting(prefix)
	for i = #MOCK.sent, 1, -1 do
		if MOCK.sent[i].text:sub(1, #prefix) == prefix then
			return MOCK.sent[i]
		end
	end
	return nil
end
local function receive(text, sender, channel)
	MOCK.fire("CHAT_MSG_ADDON", "NLPT", text, channel or "PARTY", sender)
end
local button = _G.NyteLytePaladinToolkitBuffButton

slash("holy")
assert(BM.enabled, "Blessing Manager on for Holy")
assert(button, "secure buff button created")
P.profile.blessing.assignments = {}

-- Solo: your own row is suggested from what you know (only Might at level 8 in the mocks).
local eff = BM:Effective()
assert(eff.Tester and eff.Tester.classes.PALADIN == "BLESSING_MIGHT", "solo suggestion: Might for yourself")
assert(eff.Tester.classes.MAGE == nil, "no Might on mages")

if not MOCK_NO_AURAS then
	P.Roster:Scan()
	BM:UpdateButton()
	assert(button:GetAttribute("type") == "spell", "button armed")
	assert(button:GetAttribute("spell") == "Blessing of Might", "casts Blessing of Might")
	assert(button:GetAttribute("unit") == "player", "on yourself")

	-- Once you have it (with plenty of time left), nothing to do.
	table.insert(MOCK.auras, { name = "Blessing of Might", spellId = 19740, duration = 3600, expirationTime = GetTime() + 3000 })
	P.Roster:Scan()
	assert(button:GetAttribute("type") == nil, "all blessed: button disarmed")
	-- Under 5 minutes left counts as missing again.
	MOCK.auras[#MOCK.auras].expirationTime = GetTime() + 200
	P.Roster:Scan()
	assert(button:GetAttribute("unit") == "player", "refresh when under 5 minutes")
	table.remove(MOCK.auras)
end

-- Join a group: HELLO + REQ go out (after the queue drains).
MOCK.sent = {}
MOCK.inGroup = true
MOCK.party = {
	{ unit = "party1", name = "Tankadin", class = "PALADIN" },
	{ unit = "party2", name = "Stabby", class = "ROGUE" },
	{ unit = "party3", name = "Frosty", class = "MAGE" },
}
MOCK.fire("GROUP_ROSTER_UPDATE")
settle()
flush()
local sent = table.concat(sentTexts(), "\n")
assert(sent:find("PARTY HELLO|", 1, true), "HELLO sent to party: " .. sent)
assert(sent:find("PARTY REQ", 1, true), "REQ sent")
assert(#BM:Paladins() == 2 and BM:Paladins()[1] == "Tester", "you first, then Tankadin")

-- A peer introduces themselves; we answer once.
MOCK.sent = {}
receive("HELLO|0.4.0|KI,MI,WI|DE,RE", "Tankadin-Beta Realm")
flush()
assert(BM.peers.Tankadin and BM.peers.Tankadin.blessings.BLESSING_KINGS, "peer knowledge stored")
assert(lastSentStarting("HELLO|"), "introduced ourselves back")
MOCK.sent = {}
receive("HELLO|0.4.0|KI,MI,WI|DE,RE", "Tankadin-Beta Realm")
flush()
assert(lastSentStarting("HELLO|") == nil, "only once")

-- Rows: a paladin sets their own row; others can't set ours unless leader.
local A = P.profile.blessing.assignments
receive("ROW|1|100|Tankadin|RE|WA=KI,RO=KI,MA=WI", "Tankadin")
assert(A.Tankadin and A.Tankadin.classes.WARRIOR == "BLESSING_KINGS" and A.Tankadin.aura == "AURA_RETRIBUTION", "own row accepted")
receive("ROW|1|100|Tester|DE|WA=MI", "Tankadin")
assert(A.Tester == nil, "non-leader can't set our row")
MOCK.leader = "party1"
receive("ROW|1|100|Tester|DE|WA=MI,RO=MI", "Tankadin")
assert(A.Tester and A.Tester.classes.ROGUE == "BLESSING_MIGHT", "leader can set our row")
receive("ROW|1|50|Tester|DE|WA=WI", "Tankadin")
assert(A.Tester.classes.WARRIOR == "BLESSING_MIGHT", "older update ignored")
MOCK.leader = nil

-- Garbage and non-group channels are ignored.
receive("ROW|x|y|Tester||", "Tankadin")
receive(string.rep("A", 300), "Tankadin")
receive("ROW|9|999|Tester|DE|WA=WI", "Tankadin", "WHISPER")
assert(A.Tester.classes.WARRIOR == "BLESSING_MIGHT", "garbage/whispers ignored")

-- Local edits: our row yes, theirs no (we aren't leader).
MOCK.sent = {}
assert(BM:SetAssignment("Tester", "MAGE", "BLESSING_WISDOM") == true)
assert(BM:SetAssignment("Tankadin", "MAGE", "BLESSING_MIGHT") == false, "can't edit another paladin's row")
flush()
local row = lastSentStarting("ROW|")
assert(row and row.text:find("|Tester|", 1, true) and row.text:find("MA=WI", 1, true), "edit synced: " .. tostring(row and row.text))

-- Buff button targets the first member missing *our* assignment (Stabby, rogue, Might).
if not MOCK_NO_AURAS then
	MOCK.auras[#MOCK.auras + 1] = { name = "Blessing of Might", spellId = 19740, duration = 3600, expirationTime = GetTime() + 3000 }
	P.Roster:Scan()
	assert(button:GetAttribute("unit") == "party2", "targets Stabby, got " .. tostring(button:GetAttribute("unit")))
	assert(button:GetAttribute("spell") == "Blessing of Might")
	table.remove(MOCK.auras)
end

-- Combat: no attribute changes, no sends; both happen after combat.
MOCK.combat = true
local unitBefore = button:GetAttribute("unit")
MOCK.party[2].name = "Renamed"
P.Roster:Scan() -- refuses in combat
BM:UpdateButton()
assert(button:GetAttribute("unit") == unitBefore, "secure attributes untouched in combat")
MOCK.sent = {}
BM:SetAssignment("Tester", "HUNTER", "BLESSING_MIGHT")
flush()
assert(#sentTexts() == 0, "nothing sent in combat")
MOCK.combat = false
MOCK.party[2].name = "Stabby"
MOCK.fire("PLAYER_REGEN_ENABLED")
settle()
flush()
assert(lastSentStarting("ROW|"), "queued row sent after combat")

-- Encounters hold messages too.
MOCK.fire("ENCOUNTER_START", 1, "Boss", 1, 10)
MOCK.sent = {}
BM:SetAssignment("Tester", "PRIEST", "BLESSING_WISDOM")
flush()
assert(#sentTexts() == 0, "nothing sent during an encounter")
MOCK.fire("ENCOUNTER_END", 1, "Boss", 1, 10, 1)
flush()
assert(lastSentStarting("ROW|"), "sent after the encounter")

-- Auto-suggest as a non-leader only changes our row.
local theirs = A.Tankadin.seq
BM:ApplySuggestion()
assert(A.Tankadin.seq == theirs, "other rows untouched when not leader")
MOCK.leader = "player"
BM:ApplySuggestion()
assert(A.Tankadin.seq == theirs + 1, "leader's suggestion covers everyone")
MOCK.leader = nil

-- Grid and announce.
slash("bless")
P.BlessingGrid:Refresh()
slash("bless")
MOCK.chat = {}
BM:Announce()
assert(#MOCK.chat >= 1 and MOCK.chat[1].channel == "PARTY", "announce posts to party")

-- REQ: we resend rows we authored.
MOCK.sent = {}
receive("REQ", "Tankadin")
flush()
assert(lastSentStarting("ROW|"), "REQ answered")

-- Leaving the group drops pending sends.
MOCK.inGroup = false
MOCK.party = {}
MOCK.fire("GROUP_ROSTER_UPDATE")
settle()
BM:SetAssignment("Tester", "DRUID", "BLESSING_WISDOM")
flush()
assert(P.Comm:Pending() == 0, "queue dropped when solo")

-- Module toggles off and on live.
P.Config:SetModuleEnabled("BlessingManager", "holy", false)
settle()
assert(not BM.enabled)
P.Config:SetModuleEnabled("BlessingManager", "holy", true)
settle()
assert(BM.enabled)

M4_OK = true
