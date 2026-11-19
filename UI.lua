-- Small UI helpers shared by the badge and the window, in the same style as Adventure
-- Guide Forever.

local _, P = ...

-- A dark parchment panel with a gold border.
function P.Backdrop(frame, alpha)
	if not frame.SetBackdrop then
		-- Same as inheriting BackdropTemplate: mix in, then keep the border sized.
		Mixin(frame, BackdropTemplateMixin)
		frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
	end
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.06, 0.05, 0.04, alpha or 0.9)
	frame:SetBackdropBorderColor(0.55, 0.45, 0.3, 1)
end

function P.Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	return fs
end
