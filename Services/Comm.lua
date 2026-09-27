local _, PK = ...

-- Addon-message channel for the Blessing Manager (prefix NLPT).
-- Outgoing messages are queued and only sent when all of these hold:
--  * the client allows addon messages (not in combat on Forever, probe #2),
--  * not in a boss encounter,
--  * the player is in a group (PARTY or RAID; never whispers or public chat).
-- The queue drains slowly (one message every 0.25s). Duplicate keys replace
-- older queued messages, so a burst of grid edits sends only the latest row.
-- Incoming messages fire PK_COMM_MESSAGE(text, senderShortName).

local Compat = PK.Compat
local Comm = { prefix = "NLPT", queue = {}, order = {}, inEncounter = false }
-- What happened on the wire, for /ptk sync and bug reports (copied into the
-- saved data on logout).
Comm.stats = { sent = 0, received = 0, echoes = 0, ignored = 0 }
PK.Comm = Comm

local SEND_INTERVAL = 0.25
local ticker

function Comm:Channel()
	if IsInRaid and IsInRaid() then
		return "RAID"
	elseif IsInGroup and IsInGroup() then
		return "PARTY"
	end
	return nil
end

-- Returns true, or false and a short reason.
function Comm:CanSend()
	if self.inEncounter then
		return false, "boss encounter"
	end
	if not self:Channel() then
		return false, "not in a group"
	end
	return Compat.CanSendAddonMessages()
end

-- Queues a message. key: optional; a newer message with the same key replaces it.
function Comm:Send(text, key)
	if type(text) ~= "string" or #text > 250 or not self:Channel() then
		return -- nothing to sync with when solo
	end
	key = key or text
	if not self.queue[key] then
		self.order[#self.order + 1] = key
	end
	self.queue[key] = text
	self:StartTicker()
end

function Comm:Pending()
	return #self.order
end

function Comm:Flush()
	if #self.order == 0 then
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		return
	end
	local can, why = self:CanSend()
	if not can then
		self.stats.blocked = why
		if not self:Channel() then
			-- Not in a group: nothing to sync with; drop the queue.
			self.queue, self.order = {}, {}
		end
		return
	end
	self.stats.blocked = nil
	local key = table.remove(self.order, 1)
	local text = self.queue[key]
	self.queue[key] = nil
	local send = Compat.Resolve("C_ChatInfo.SendAddonMessage")
	if send and text then
		local ok, result = pcall(send, self.prefix, text, self:Channel())
		local s = self.stats
		s.sent = s.sent + 1
		-- SendAddonMessage returns an Enum.SendAddonMessageResult (0 = success).
		s.lastResult = ok and (Compat.IsSecret(result) and "<secret>" or tostring(result)) or ("error: " .. tostring(result))
		s.lastSent = text:match("^(%u+)")
		s.lastSentAt = time()
		PK:Debug("Comm send %s -> %s", tostring(text), s.lastResult)
	end
end

function Comm:StartTicker()
	if not ticker and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(SEND_INTERVAL, function()
			Comm:Flush()
		end)
	elseif not C_Timer.NewTicker then
		self:Flush()
	end
end

-- Short name for a sender ("Name-Realm" -> "Name" on the same realm).
function Comm.ShortName(name)
	if type(name) ~= "string" then
		return nil
	end
	if Ambiguate then
		local ok, short = pcall(Ambiguate, name, "none")
		if ok and type(short) == "string" then
			return short
		end
	end
	return (name:match("^([^-]+)")) or name
end

function Comm.PlayerName()
	return UnitName("player")
end

PK:On("PK_READY", Comm, function()
	local register = Compat.Resolve("C_ChatInfo.RegisterAddonMessagePrefix")
	if register then
		pcall(register, Comm.prefix)
	end
end)

PK:RegisterEvent("CHAT_MSG_ADDON", Comm, function(_, _, prefix, text, channel, sender)
	if Compat.IsSecret(prefix) or prefix ~= Comm.prefix then
		return
	end
	local s = Comm.stats
	if Compat.IsSecret(text) or Compat.IsSecret(sender) or type(text) ~= "string" then
		s.ignored = s.ignored + 1
		s.lastIgnored = "secret or non-text payload"
		return
	end
	if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then
		s.ignored = s.ignored + 1
		s.lastIgnored = "channel " .. tostring(channel)
		return
	end
	local short = Comm.ShortName(sender)
	if not short or short == Comm.PlayerName() then
		s.echoes = s.echoes + 1 -- our own message coming back
		return
	end
	s.received = s.received + 1
	s.lastFrom = short
	s.lastFromRaw = tostring(sender)
	s.lastReceived = text:match("^(%u+)")
	s.lastReceivedAt = time()
	PK:Debug("Comm recv from %s (%s): %s", short, tostring(sender), text)
	PK:Fire("PK_COMM_MESSAGE", text, short)
end)

PK:RegisterEvent("PLAYER_LOGOUT", Comm, function()
	if PK.db then
		PK.db.commStats = Comm.stats
	end
end)

PK:RegisterEvent("ENCOUNTER_START", Comm, function()
	Comm.inEncounter = true
end)
PK:RegisterEvent("ENCOUNTER_END", Comm, function()
	Comm.inEncounter = false
	Comm:StartTicker()
end)
PK:RegisterEvent("PLAYER_REGEN_ENABLED", Comm, function()
	Comm:StartTicker()
end)
