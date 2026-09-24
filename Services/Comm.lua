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

function Comm:CanSend()
	return not self.inEncounter and Compat.CanSendAddonMessages() and self:Channel() ~= nil
end

-- Queues a message. key: optional; a newer message with the same key replaces it.
function Comm:Send(text, key)
	if type(text) ~= "string" or #text > 250 then
		return
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
	if not self:CanSend() then
		if not self:Channel() then
			-- Not in a group: nothing to sync with; drop the queue.
			self.queue, self.order = {}, {}
		end
		return
	end
	local key = table.remove(self.order, 1)
	local text = self.queue[key]
	self.queue[key] = nil
	local send = Compat.Resolve("C_ChatInfo.SendAddonMessage")
	if send and text then
		local ok, err = pcall(send, self.prefix, text, self:Channel())
		PK:Debug("Comm send %s: %s", tostring(ok), tostring(ok and text or err))
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
	if Compat.IsSecret(text) or Compat.IsSecret(sender) or type(text) ~= "string" then
		return
	end
	if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then
		return
	end
	local short = Comm.ShortName(sender)
	if not short or short == Comm.PlayerName() then
		return -- our own echo
	end
	PK:Fire("PK_COMM_MESSAGE", text, short)
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
