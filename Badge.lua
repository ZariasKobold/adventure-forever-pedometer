-- The step counter: a small badge beside the minimap's calendar button showing your steps
-- on foot this session (since you logged in). Hover for this session vs all time; click to
-- open the pedometer window. Drag it anywhere; right-click puts it back by the calendar.
-- Turn it off in the window or with /pedometer badge.

local _, P = ...

local ICON = "Interface\\Icons\\Ability_Tracking" -- a trail of footprints
local badge

-- Just under the zone name, left of the calendar's corner, or wherever you dragged it.
-- The default follows the minimap cluster, so it moves along if Edit Mode moves the minimap.
local DEFAULT_X, DEFAULT_Y = -54, -61

local function place(f)
	f:ClearAllPoints()
	local saved = P.db.options.badgePosition
	if type(saved) == "table" and saved.point then
		f:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
	else
		f:SetPoint("TOPRIGHT", MinimapCluster or UIParent, "TOPRIGHT", DEFAULT_X, DEFAULT_Y)
	end
end

local function showTooltip(f)
	local rec = P:Mine()
	if not rec then return end
	local session = rec.session
	GameTooltip:SetOwner(f, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText("Steps", 1, 1, 1)
	GameTooltip:AddDoubleLine("This session",
		string.format("%s steps", P.Commas(P.StepsFrom(session.distance.foot))), nil, nil, nil, 1, 0.82, 0)
	GameTooltip:AddDoubleLine("All time",
		string.format("%s steps", P.Commas(P.StepsFrom(rec.distance.foot))), nil, nil, nil, 1, 0.82, 0)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Distance traveled, every way", 1, 1, 1)
	GameTooltip:AddDoubleLine("This session", P.Distance(P.TotalYards(session.distance)), nil, nil, nil, 1, 1, 1)
	GameTooltip:AddDoubleLine("All time", P.Distance(P.TotalYards(rec.distance)), nil, nil, nil, 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click to open the pedometer. Drag to move it; right-click to put it back by the calendar.",
		0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function create()
	local f = CreateFrame("Button", nil, UIParent)
	P.Backdrop(f, 0.85)
	f:SetSize(70, 22)
	-- Above the minimap cluster, whose zone bar and buttons sit over MEDIUM frames and
	-- were catching the mouse when you tried to grab the badge.
	f:SetFrameStrata("HIGH")
	f:SetFrameLevel(20)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", 5, 0)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local text = P.Text(f, "GameFontHighlightSmall")
	text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	f.text = text

	f:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:StartMoving()
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		P.db.options.badgePosition = { point = point, relPoint = relPoint, x = x, y = y }
		place(self)
		C_Timer.After(0, function() self.dragging = nil end) -- don't treat the drop as a click
	end)
	f:SetScript("OnClick", function(self, button)
		if self.dragging then return end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if button == "RightButton" then
			P.db.options.badgePosition = nil
			place(self)
			return
		end
		P:ToggleWindow()
	end)
	f:SetScript("OnEnter", showTooltip)
	f:SetScript("OnLeave", GameTooltip_Hide)
	place(f)
	return f
end

-- Redraws the count (called as you move) and shows or hides it per the option.
function P:UpdateBadge()
	if not self.db then return end
	if not self:Option("badge") then
		if badge then badge:Hide() end
		return
	end
	local rec = self:Mine()
	if not rec then return end
	badge = badge or create()
	local text = P.Commas(P.StepsFrom(rec.session.distance.foot))
	if badge.text:GetText() ~= text then
		badge.text:SetText(text)
		badge:SetWidth(math.max(50, badge.text:GetStringWidth() + 30))
	end
	badge:Show()
	if GameTooltip:IsOwned(badge) then showTooltip(badge) end
end

local handlers = {
	-- After Pedometer.lua has started this session's record, and after the minimap is laid out.
	PLAYER_ENTERING_WORLD = function() C_Timer.After(0, function() P:UpdateBadge() end) end,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
	if not P.db then return end
	local ok, err = pcall(handlers[event], ...)
	if not ok and P.debug then P:Print("Badge error in %s: %s", event, tostring(err)) end
end)
