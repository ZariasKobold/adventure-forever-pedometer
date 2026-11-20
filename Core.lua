-- Adventure Forever Pedometer
-- Core: namespace, saved variables, the /pedometer command, and bringing over the distance
-- and visit counts Adventure Guide Forever kept before they moved here.

-- Globals this addon creates, on purpose (everything else lives on the namespace P):
--   AdventureForeverPedometerDB                   saved variables
--   SLASH_ADVENTUREFOREVERPEDOMETER1/2, SlashCmdList  the /pedometer and /steps commands
--   AdventureForeverPedometer_OnCompartmentClick  addon compartment entry (TOC)
--   AdventureForeverPedometerFrame                the window (Escape closes it)

local ADDON, P = ...

P.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

local PREFIX = "|cff66ccffPedometer|r "

function P:Print(fmt, ...)
	local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
	print(PREFIX .. msg)
end

-- Secret values (Midnight-era addon restrictions, active on Forever) can be passed around
-- but not compared, truth-tested, or stored. Readable returns nil for one.
local function isSecret(value)
	return type(issecretvalue) == "function" and issecretvalue(value) == true
end

function P:Readable(value)
	if isSecret(value) then return nil end
	return value
end

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------

local defaults = {
	characters = {},     -- [name-realm] = distance traveled and places visited (never leaves your computer)
	options = {
		badge = true,    -- step counter beside the minimap's calendar button
		-- badgePosition = { point, relPoint, x, y } once you drag it
	},
}

local function applyDefaults(db, defs)
	for k, v in pairs(defs) do
		if db[k] == nil then
			db[k] = type(v) == "table" and CopyTable(v) or v
		elseif type(v) == "table" and type(db[k]) == "table" then
			applyDefaults(db[k], v)
		end
	end
end

function P:Option(name)
	return self.db and self.db.options[name] == true
end

function P:SetOption(name, value)
	self.db.options[name] = value and true or false
	if name == "badge" and self.UpdateBadge then self:UpdateBadge() end
end

-- Adventure Guide Forever counted distance itself until v0.7.1 (AdventureGuideForeverDB
-- .journey[character].distance). Bring it over once, so nobody loses their miles. Returns
-- how many characters it brought over.
function P:ImportFromGuide(guideDB)
	if self.db.importedFromGuide then return 0 end
	if type(guideDB) ~= "table" or type(guideDB.journey) ~= "table" then return 0 end
	local count = 0
	for key, old in pairs(guideDB.journey) do
		if type(key) == "string" and type(old) == "table" and type(old.distance) == "table" then
			local rec = self:GetRecord(key)
			for kind, yards in pairs(old.distance) do
				if type(yards) == "number" and rec.distance[kind] then
					rec.distance[kind] = rec.distance[kind] + yards
				end
			end
			if type(old.combat) == "number" then rec.combat = rec.combat + old.combat end
			if type(old.class) == "string" then rec.class = rec.class or old.class end
			count = count + 1
		end
	end
	self.db.importedFromGuide = true
	return count
end

------------------------------------------------------------------------
-- /pedometer
------------------------------------------------------------------------

local USAGE = "|cffffd100/pedometer|r: open your distance traveled.  |cffffd100/pedometer places|r: the "
	.. "dungeons, raids, and zones you've visited.  |cffffd100/pedometer badge|r: the step counter by the "
	.. "minimap on or off.  |cffffd100/pedometer status|r: what the pedometer sees right now."

local commands = {
	[""] = function() P:ToggleWindow() end,
	show = function() P:ToggleWindow() end,
	places = function() P:ShowWindow("places") end,
	visits = function() P:ShowWindow("places") end,
	help = function() P:Print(USAGE) end,
	badge = function()
		P:SetOption("badge", not P:Option("badge"))
		P:Print("Step counter is now %s.", P:Option("badge") and "|cff20ff20on|r" or "|cffff2020off|r")
	end,
	status = function()
		local st = P:Status()
		P:Print("Measuring by %s, %s, counting as %s. Speed %s, on a flight path: %s, swimming: %s.",
			st.mode, st.ticking and "running" or "idle", st.kind, st.speed and string.format("%.1f", st.speed) or "hidden",
			st.onTaxi and "yes" or "no", st.swimming and "yes" or "no")
	end,
}

SLASH_ADVENTUREFOREVERPEDOMETER1 = "/pedometer"
SLASH_ADVENTUREFOREVERPEDOMETER2 = "/steps"
SlashCmdList.ADVENTUREFOREVERPEDOMETER = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local fn = commands[msg] or commands.help
	fn()
end

function AdventureForeverPedometer_OnCompartmentClick()
	P:ToggleWindow()
end

------------------------------------------------------------------------
-- Load
------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {
	ADDON_LOADED = function(name)
		if name ~= ADDON then return end
		AdventureForeverPedometerDB = AdventureForeverPedometerDB or {}
		applyDefaults(AdventureForeverPedometerDB, defaults)
		P.db = AdventureForeverPedometerDB
	end,
	-- Every addon's saved variables are loaded by now, so the guide's old counts are readable.
	PLAYER_LOGIN = function()
		local n = P:ImportFromGuide(AdventureGuideForeverDB)
		if n > 0 then
			P:Print("Brought over the distance Adventure Guide Forever counted for %d character%s.", n, n == 1 and "" or "s")
		end
		local v = P:ImportVisits(AdventureGuideForeverDB)
		if v > 0 then
			P:Print("Brought over the places Adventure Guide Forever counted for %d character%s. See them with /pedometer places.",
				v, v == 1 and "" or "s")
		end
	end,
}
for event in pairs(handlers) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
	local ok, err = pcall(handlers[event], ...)
	if not ok and P.debug then P:Print("Error in %s: %s", event, tostring(err)) end
end)
