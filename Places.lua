-- Places: how many times each character has been to each dungeon, raid, and zone, and
-- when last. Adventure Guide Forever kept these until v0.9.0 (AdventureGuideForeverDB
-- .journey); they're brought over once, at login (P:ImportVisits).
--
-- Saved per character in AdventureForeverPedometerDB.characters[key].places, keyed by the
-- place's name, lowercased without "The " or punctuation, so "The Deadmines" and
-- "Deadmines" are the same place. Never leaves your computer.

local _, P = ...

local INSTANCE_KINDS = { party = "dungeon", raid = "raid" }

-- "The Deadmines" -> "deadmines".
function P.PlaceKey(name)
	if type(name) ~= "string" or name == "" then return nil end
	local key = name:lower():gsub("^the ", ""):gsub("[^%w]", "")
	return key ~= "" and key or nil
end

-- Counts one visit to a place in a record's list.
local function count(places, key, name, kind, visits, last)
	local v = places[key] or { name = name, kind = kind, visits = 0, last = 0 }
	v.visits = v.visits + (visits or 1)
	v.last = math.max(v.last or 0, last or time())
	if kind ~= "zone" then v.kind = kind end -- an instance name wins over a zone of the same name
	places[key] = v
	return v
end

-- Where you are now: name, key, kind ("dungeon", "raid", or "zone").
function P:WhereAmI()
	local name, instanceType = GetInstanceInfo()
	name, instanceType = self:Readable(name), self:Readable(instanceType)
	local kind = INSTANCE_KINDS[instanceType]
	if not kind then
		name, kind = self:Readable(GetRealZoneText()), "zone"
	end
	local key = self.PlaceKey(name)
	if key then return name, key, kind end
end

-- Counts a visit when you arrive somewhere new. Where you are is saved, so a reload or
-- relog in the same spot doesn't count again.
function P:Arrive()
	local rec = self:Mine()
	if not rec then return end
	rec.places = rec.places or {}
	local name, key, kind = self:WhereAmI()
	if not key or rec.here == key then return end
	rec.here = key
	count(rec.places, key, name, kind)
	if self.RefreshWindow then self:RefreshWindow() end
end

-- Every character's visits added together.
function P:PlaceTotals()
	local total = {}
	for _, rec in pairs(self.db.characters) do
		for key, v in pairs(rec.places or {}) do
			count(total, key, v.name, v.kind, v.visits or 0, v.last or 0)
		end
	end
	return total
end

-- A record's places of one group ("instances": dungeons and raids, or "zones"), most
-- visited first.
function P.SortedPlaces(places, group)
	local out = {}
	for _, v in pairs(places or {}) do
		local isZone = v.kind == "zone"
		if (group == "zones") == isZone then out[#out + 1] = v end
	end
	table.sort(out, function(a, b)
		if a.visits ~= b.visits then return a.visits > b.visits end
		return (a.name or "") < (b.name or "")
	end)
	return out
end

-- "today", "yesterday", "5 days ago".
function P.Ago(when, now)
	if type(when) ~= "number" or when <= 0 then return nil end
	local days = math.floor(((now or time()) - when) / 86400)
	if days <= 0 then return "today" end
	if days == 1 then return "yesterday" end
	return string.format("%d days ago", days)
end

-- Brings over the visit counts Adventure Guide Forever kept, once. Returns how many
-- characters it brought over.
function P:ImportVisits(guideDB)
	if self.db.importedVisits then return 0 end
	if type(guideDB) ~= "table" or type(guideDB.journey) ~= "table" then return 0 end
	local n = 0
	for charKey, old in pairs(guideDB.journey) do
		if type(charKey) == "string" and type(old) == "table" then
			local rec = self:GetRecord(charKey)
			rec.places = rec.places or {}
			local names = type(old.instanceNames) == "table" and old.instanceNames or {}
			local any = false
			for instKey, v in pairs(type(old.instances) == "table" and old.instances or {}) do
				local name = names[instKey] or instKey
				local key = self.PlaceKey(name)
				if key and type(v) == "table" and type(v.visits) == "number" then
					count(rec.places, key, name, "dungeon", v.visits, v.last)
					any = true
				end
			end
			for zone, v in pairs(type(old.zones) == "table" and old.zones or {}) do
				local key = self.PlaceKey(zone)
				if key and type(v) == "table" and type(v.visits) == "number" then
					count(rec.places, key, zone, "zone", v.visits, v.last)
					any = true
				end
			end
			-- Where the guide last saw you, so arriving there now doesn't count twice.
			local here = old.here and (names[old.here] or old.here) or old.lastZone
			rec.here = rec.here or self.PlaceKey(here)
			if type(old.class) == "string" then rec.class = rec.class or old.class end
			if any then n = n + 1 end
		end
	end
	self.db.importedVisits = true
	return n
end

local handlers = {
	PLAYER_ENTERING_WORLD = function() P:Arrive() end,
	ZONE_CHANGED_NEW_AREA = function() P:Arrive() end,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
	if not P.db then return end
	local ok, err = pcall(handlers[event], ...)
	if not ok and P.debug then P:Print("Places error in %s: %s", event, tostring(err)) end
end)
