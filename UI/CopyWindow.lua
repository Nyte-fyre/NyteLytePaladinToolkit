local _, PK = ...

-- A movable window with a scrollable text box. Two modes:
--  * Show(title, text): read-only, for probe output, logs, errors and exports.
--    "Select all" is a button because clicking into an EditBox can clear a
--    script-driven selection.
--  * ShowInput(title, hint, onAccept): editable, for pasting an import
--    string; the accept button calls onAccept(text).

local CopyWindow = {}
PK.CopyWindow = CopyWindow

local frame, editBox, titleText, scroll, selectAll, accept, hint
local mode, onAcceptFn

local function Build()
	frame = PK.Theme.CreateWindow("NyteLytePaladinToolkitCopyWindow", PK.displayName, 720, 540)
	titleText = frame.titleText

	scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 16, -52)
	scroll:SetPoint("BOTTOMRIGHT", -36, 46)

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
	-- Read-only mode: typing restores the original text.
	editBox:SetScript("OnTextChanged", function(self, userInput)
		if mode == "read" and userInput and self.original then
			self:SetText(self.original)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(editBox)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function()
		editBox:SetFocus()
	end)

	selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	selectAll:SetSize(120, 24)
	selectAll:SetPoint("BOTTOMLEFT", 16, 14)
	selectAll:SetText("Select all")
	selectAll:SetScript("OnClick", function()
		editBox:SetFocus()
		editBox:HighlightText()
	end)

	accept = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	accept:SetSize(120, 24)
	accept:SetPoint("BOTTOMLEFT", 16, 14)
	accept:SetText("Import")
	accept:SetScript("OnClick", function()
		if onAcceptFn and onAcceptFn(editBox:GetText()) then
			frame:Hide()
		end
	end)

	hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(90, 24)
	close:SetPoint("BOTTOMRIGHT", -16, 14)
	close:SetText("Close")
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
end

function CopyWindow:Show(title, text)
	if not frame then
		Build()
	end
	mode = "read"
	selectAll:Show()
	accept:Hide()
	hint:SetText("then Ctrl+C to copy. Esc closes.")
	titleText:SetText(title or PK.displayName)
	editBox.original = text or ""
	editBox:SetText(editBox.original)
	editBox:SetCursorPosition(0)
	scroll:SetVerticalScroll(0)
	frame:Show()
end

-- onAccept(text) returns true to close the window (e.g. after a successful import).
function CopyWindow:ShowInput(title, hintText, onAccept)
	if not frame then
		Build()
	end
	mode = "input"
	onAcceptFn = onAccept
	selectAll:Hide()
	accept:Show()
	hint:SetText(hintText or "Paste with Ctrl+V.")
	titleText:SetText(title or PK.displayName)
	editBox.original = nil
	editBox:SetText("")
	scroll:SetVerticalScroll(0)
	frame:Show()
	editBox:SetFocus()
end

function CopyWindow:Hide()
	if frame then
		frame:Hide()
	end
end
