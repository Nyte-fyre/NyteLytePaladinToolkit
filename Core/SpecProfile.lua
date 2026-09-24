local _, PK = ...

-- The spec choice node: mode (auto/holy/prot/ret) -> effective spec, which
-- decides which modules run. Manual choice always wins; Auto uses talent
-- points when available, else known tree-specific spells, else Holy.
-- Fires PK_SPEC_CHANGED(spec, previous) when the effective spec changes and
-- PK_SPEC_EVALUATED(decision) after every evaluation (for the settings UI).

local Decision = PK.SpecDecision
local SP = {}
PK.SpecProfile = SP

SP.LABELS = { auto = "Auto", holy = "Holy", prot = "Protection", ret = "Retribution" }

function SP:GetSpec()
	return self.decision and self.decision.spec or Decision.FALLBACK
end

function SP:GetDecision()
	return self.decision
end

function SP:GatherInput()
	local points = PK.Compat.GetTalentPointsByTree()
	return {
		talentPoints = points,
		knownSpecSpells = PK.SpellRegistry:CountKnownBySpec(),
	}
end

-- Enables/disables feature modules to match the matrix for the current spec,
-- and tells enabled modules about the spec.
function SP:ApplyModuleStates()
	local spec = self:GetSpec()
	for _, name in ipairs(PK.moduleOrder) do
		local m = PK.modules[name]
		if not m.alwaysOn then
			if PK.Config:IsModuleEnabled(name, spec) then
				PK:EnableModule(name)
				if m.OnSpecChanged then
					PK.SafeCall(m.OnSpecChanged, m, spec)
				end
			else
				PK:DisableModule(name)
			end
		end
	end
end

function SP:Evaluate()
	if not PK.profile then
		return
	end
	local previous = self.decision and self.decision.spec
	self.decision = Decision.Decide(PK.profile.specMode, self:GatherInput())
	local d = self.decision
	PK:Debug("Spec: %s (%s, %s)", d.spec, d.confidence, d.method)
	if d.spec ~= previous then
		self:ApplyModuleStates()
		PK:Fire("PK_SPEC_CHANGED", d.spec, previous)
	end
	PK:Fire("PK_SPEC_EVALUATED", d)
end

function SP:SetMode(mode)
	if mode ~= "auto" and not Decision.IsSpec(mode) then
		return
	end
	PK.profile.specMode = mode
	self:Evaluate()
	local d = self.decision
	if mode == "auto" then
		PK:Print(string.format("spec mode Auto: using %s (%s).", SP.LABELS[d.spec], SP:DescribeDetection(d.detected)))
	else
		PK:Print("spec set to " .. SP.LABELS[mode] .. ".")
	end
end

function SP:Cycle()
	self:SetMode(Decision.NextMode(PK.profile.specMode))
end

-- "detected Holy, low confidence, from known spells" style text.
function SP:DescribeDetection(detected)
	if not detected then
		return "not detected yet"
	end
	if detected.confidence == "none" then
		return "could not detect; defaulting to " .. SP.LABELS[detected.spec]
	end
	return string.format("detected %s, %s confidence, from %s", SP.LABELS[detected.spec], detected.confidence,
		detected.method)
end

local function queueEvaluate()
	PK:Debounce("SpecProfile", 0.5, function()
		SP:Evaluate()
	end)
end

PK:On("PK_READY", SP, function()
	PK.SpellRegistry:Refresh()
	SP:Evaluate()
end)
PK:On("PK_SPELLS_UPDATED", SP, queueEvaluate)
PK:On("PK_PROFILE_CHANGED", SP, function()
	SP.decision = nil -- force modules to re-apply for the new profile
	SP:Evaluate()
end)
PK:On("PK_MODULES_CHANGED", SP, function()
	SP:ApplyModuleStates()
end)
for _, event in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
	"TRAIT_CONFIG_UPDATED", "PLAYER_ENTERING_WORLD" }) do
	PK:RegisterEvent(event, SP, queueEvaluate)
end

-- Commands -----------------------------------------------------------------------------

for _, mode in ipairs(Decision.MODES) do
	PK:RegisterCommand(mode, function()
		SP:SetMode(mode)
	end, mode == "auto" and "detect spec automatically" or ("use " .. SP.LABELS[mode] .. " settings"))
end

PK:RegisterCommand("spec", function()
	local d = SP.decision
	if not d then
		PK:Print("spec not evaluated yet.")
		return
	end
	PK:Print(string.format("mode %s, active spec %s; %s.", SP.LABELS[d.mode], SP.LABELS[d.spec],
		SP:DescribeDetection(d.detected)))
end, "show the active spec and what Auto detected")

-- Keybinding (Bindings.xml)
BINDING_HEADER_NYTELYTEPALADINTOOLKIT = PK.displayName
BINDING_NAME_NLPT_CYCLE_SPEC = "Cycle spec mode (Auto / Holy / Prot / Ret)"
BINDING_NAME_NLPT_TOGGLE_LOCK = "Lock / unlock frame positions"
