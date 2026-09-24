local _, PK = ...

-- A movable window with a scrollable, selectable text box, used for probe
-- output, the debug log and captured errors. "Select all" is a button
-- because clicking into an EditBox can clear a script-driven selection.

local CopyWindow = {}
PK.CopyWindow = CopyWindow

local frame, editBox, titleText, scroll

local function Build()
	frame = CreateFrame("Frame", "NyteLytePaladinToolkitCopyWindow", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(720, 520)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "NyteLytePaladinToolkitCopyWindow")

	titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	titleText:SetPoint("TOP", 0, -5)

	scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, -32)
	scroll:SetPoint("BOTTOMRIGHT", -34, 44)

	editBox = CreateFrame("EditBox", nil, scroll)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:SetMaxLetters(0)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(660)
	editBox:SetHeight(440)
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		frame:Hide()
	end)
	-- Read-only: typing restores the original text.
	editBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self.original then
			self:SetText(self.original)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(editBox)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function()
		editBox:SetFocus()
	end)

	local selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	selectAll:SetSize(120, 24)
	selectAll:SetPoint("BOTTOMLEFT", 14, 12)
	selectAll:SetText("Select all")
	selectAll:SetScript("OnClick", function()
		editBox:SetFocus()
		editBox:HighlightText()
	end)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)
	hint:SetText("then Ctrl+C to copy. Esc closes.")

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(90, 24)
	close:SetPoint("BOTTOMRIGHT", -14, 12)
	close:SetText("Close")
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
end

function CopyWindow:Show(title, text)
	if not frame then
		Build()
	end
	titleText:SetText(title or PK.displayName)
	editBox.original = text or ""
	editBox:SetText(editBox.original)
	editBox:SetCursorPosition(0)
	scroll:SetVerticalScroll(0)
	frame:Show()
end

function CopyWindow:Hide()
	if frame then
		frame:Hide()
	end
end
