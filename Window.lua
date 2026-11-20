-- The pedometer window (/pedometer, or click the badge). Two pages: Distance (each way you
-- travel, this session and all time) and Places (dungeons, raids, and zones you've visited).
-- Either can show this character or all of them together.

local _, P = ...

local MARATHON_MILES = 26.2
local MAX_CHARACTERS = 6
local MAX_PLACES = 8 -- per list on the Places page
local WIDTH, ROW = 400, 34

local window
local showAll = false
local page = "distance" -- or "places"

-- "under a minute", "25 minutes", "2 hours 5 minutes".
function P.PlayedFor(secs)
	local mins = math.floor((secs or 0) / 60)
	if mins < 1 then return "under a minute" end
	local hours, rest = math.floor(mins / 60), mins % 60
	local function unit(n, word) return string.format("%d %s%s", n, word, n == 1 and "" or "s") end
	if hours == 0 then return unit(mins, "minute") end
	return rest == 0 and unit(hours, "hour") or (unit(hours, "hour") .. " " .. unit(rest, "minute"))
end

local function characterCount()
	local n = 0
	for _ in pairs(P.db.characters) do n = n + 1 end
	return n
end

local function create()
	local f = CreateFrame("Frame", "AdventureForeverPedometerFrame", UIParent)
	P.Backdrop(f, 0.96)
	f:SetSize(WIDTH, 300)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	table.insert(UISpecialFrames, f:GetName())

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local title = P.Text(f, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Pedometer")

	-- This character / all characters.
	f.view = CreateFrame("Button", nil, f)
	f.view:SetPoint("TOPRIGHT", -34, -16)
	f.view:SetSize(170, 16)
	f.view.text = P.Text(f.view, "GameFontNormalSmall", "RIGHT")
	f.view.text:SetAllPoints()
	f.view:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		showAll = not showAll
		P:RefreshWindow()
	end)

	f.total = P.Text(f, "GameFontNormalLarge")
	f.total:SetPoint("TOPLEFT", 16, -44)
	f.total:SetPoint("RIGHT", -16, 0)
	f.total:SetTextColor(1, 1, 1)
	f.session = P.Text(f)
	f.session:SetPoint("TOPLEFT", f.total, "BOTTOMLEFT", 0, -4)
	f.session:SetPoint("RIGHT", -16, 0)
	f.session:SetTextColor(0.85, 0.85, 0.85)

	f.rows = {}
	for i, kind in ipairs(P.KINDS) do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(WIDTH - 32, ROW)
		row:SetPoint("TOPLEFT", 16, -92 - (i - 1) * ROW)
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(26, 26)
		icon:SetPoint("LEFT")
		icon:SetTexture(kind.icon)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local label = P.Text(row, "GameFontNormal")
		label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
		label:SetText(kind.label)
		row.detail = P.Text(row, "GameFontHighlightSmall")
		row.detail:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
		row.detail:SetTextColor(0.7, 0.7, 0.7)
		row.value = P.Text(row, "GameFontHighlight", "RIGHT")
		row.value:SetPoint("RIGHT", 0, 0)
		f.rows[kind.key] = row
	end

	local below = -92 - #P.KINDS * ROW - 6
	f.notes = P.Text(f, "GameFontHighlightSmall")
	f.notes:SetPoint("TOPLEFT", 16, below)
	f.notes:SetPoint("RIGHT", -16, 0)
	f.notes:SetTextColor(0.6, 0.6, 0.6)

	f.badge = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.badge:SetSize(24, 24)
	f.badge:SetPoint("BOTTOMLEFT", 12, 30)
	f.badge.label = P.Text(f, "GameFontHighlightSmall")
	f.badge.label:SetPoint("LEFT", f.badge, "RIGHT", 2, 0)
	f.badge.label:SetText("Show the step counter by the minimap's calendar")
	f.badge:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		P:SetOption("badge", self:GetChecked())
	end)

	local privacy = P.Text(f, "GameFontDisableSmall")
	privacy:SetPoint("BOTTOMLEFT", 16, 14)
	privacy:SetPoint("RIGHT", -16, 0)
	privacy:SetText("Your distance and places stay on your computer. They're never shared.")

	-- The Places page: one block of text, in place of the distance rows.
	f.places = P.Text(f)
	f.places:SetPoint("TOPLEFT", 16, -44)
	f.places:SetPoint("RIGHT", -16, 0)

	-- Switch pages.
	f.pageButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.pageButton:SetSize(130, 22)
	f.pageButton:SetPoint("BOTTOMRIGHT", -12, 32)
	f.pageButton:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		page = page == "places" and "distance" or "places"
		P:RefreshWindow()
	end)

	f:Hide()
	return f
end

-- The lines under the rows: marathons, combat, and (all characters) everyone's totals.
function P:WindowNotes(rec, all)
	local lines = {}
	local footMiles = (rec.distance.foot or 0) / P.YARDS_PER_MILE
	if footMiles >= 1 then
		local m = footMiles / MARATHON_MILES
		lines[#lines + 1] = string.format("That's %.1f marathon%s on foot.", m, m == 1 and "" or "s")
	end
	if (rec.combat or 0) > 0 then
		lines[#lines + 1] = string.format("%s of that was in combat. Charges, leaps, and knockbacks count only "
			.. "as far as you could have run.", P.Distance(rec.combat))
	end
	if all then
		local chars = {}
		for key, r in pairs(self.db.characters) do
			chars[#chars + 1] = { name = r.name or key, yards = P.TotalYards(r.distance) }
		end
		table.sort(chars, function(a, b) return a.yards > b.yards end)
		lines[#lines + 1] = " "
		for i = 1, math.min(MAX_CHARACTERS, #chars) do
			lines[#lines + 1] = string.format("|cffffd100%s|r  %s", chars[i].name, P.Distance(chars[i].yards))
		end
		if #chars > MAX_CHARACTERS then lines[#lines + 1] = string.format("...and %d more.", #chars - MAX_CHARACTERS) end
	end
	return lines
end

-- The Places page's text: dungeons and raids, then zones, most visited first.
function P:PlacesText(places, now)
	local lines = {}
	local function list(title, group)
		local sorted = P.SortedPlaces(places, group)
		lines[#lines + 1] = "|cffffd100" .. title .. "|r"
		if #sorted == 0 then
			lines[#lines + 1] = "|cff888888None yet.|r"
		end
		for i = 1, math.min(MAX_PLACES, #sorted) do
			local v = sorted[i]
			local ago = P.Ago(v.last, now)
			lines[#lines + 1] = string.format("%s%s  |cff888888%d visit%s%s|r", v.name,
				v.kind == "raid" and " |cff888888(raid)|r" or "", v.visits, v.visits == 1 and "" or "s",
				ago and (", last " .. ago) or "")
		end
		if #sorted > MAX_PLACES then
			lines[#lines + 1] = string.format("|cff888888...and %d more.|r", #sorted - MAX_PLACES)
		end
		lines[#lines + 1] = " "
	end
	list("Dungeons and raids", "instances")
	list("Zones", "zones")
	return table.concat(lines, "\n")
end

function P:RefreshWindow()
	if not window or not window:IsShown() then return end
	local mine = self:Mine()
	if not mine then return end
	local all = showAll and characterCount() > 1

	window.view:SetShown(characterCount() > 1)
	window.view.text:SetText(all and "All characters (click for this one)" or "This character (click for all)")
	window.badge:SetChecked(self:Option("badge"))
	local onPlaces = page == "places"
	window.pageButton:SetText(onPlaces and "Distance" or "Places visited")
	window.total:SetShown(not onPlaces)
	window.session:SetShown(not onPlaces)
	window.notes:SetShown(not onPlaces)
	for _, row in pairs(window.rows) do row:SetShown(not onPlaces) end
	window.places:SetShown(onPlaces)
	if onPlaces then
		window.places:SetText(self:PlacesText(all and self:PlaceTotals() or mine.places))
		window:SetHeight(44 + window.places:GetStringHeight() + 72)
		return
	end

	local rec = all and self:Totals() or mine
	local session = mine.session
	window.total:SetText(string.format("You've traveled |cffffd100%s|r%s.", P.Distance(P.TotalYards(rec.distance)),
		all and " across all characters" or ""))
	window.session:SetText(string.format("This session: |cffffd100%s|r and |cffffd100%s|r steps in %s.",
		P.Distance(P.TotalYards(session.distance)), P.Commas(P.StepsFrom(session.distance.foot)),
		P.PlayedFor(time() - (session.started or time()))))
	for _, kind in ipairs(P.KINDS) do
		local row = window.rows[kind.key]
		local yards, now = rec.distance[kind.key] or 0, session.distance[kind.key] or 0
		if kind.key == "foot" then
			row.detail:SetText(string.format("%s steps this session, about %s in all",
				P.Commas(P.StepsFrom(now)), P.Commas(P.StepsFrom(yards))))
		else
			row.detail:SetText("This session: " .. P.Distance(now))
		end
		row.value:SetText(P.Distance(yards))
	end
	window.notes:SetText(table.concat(self:WindowNotes(rec, all), "\n"))
	-- Grow to fit the notes.
	window:SetHeight(92 + #P.KINDS * ROW + 6 + window.notes:GetStringHeight() + 64)
end

function P:ToggleWindow()
	if not self.db then return end
	window = window or create()
	if window:IsShown() then
		window:Hide()
	else
		window:Show()
		self:RefreshWindow()
	end
end

-- Opens the window on a page ("distance" or "places").
function P:ShowWindow(which)
	if not self.db then return end
	window = window or create()
	page = which or page
	window:Show()
	self:RefreshWindow()
end
