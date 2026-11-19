-- The pedometer: how far you've traveled on foot, mounted, flying, swimming, and by flight
-- path, per character, all time and this session.
--
--   * In the open world it measures how far you actually moved (UnitPosition, in yards),
--     which works for flight paths and swimming, where the movement events and the
--     reported speed can't be trusted.
--   * Inside dungeons the game hides your position, so it samples your speed instead, only
--     while you move.
--   * This session: the same distances since you logged in (a /reload keeps counting).
--
-- Fights skew a speed-based pedometer, so combat has its own rules (see P.Pace): charges and
-- leaps spike your speed, knockbacks fling you without a single step, and the game may hide
-- your speed as a secret value mid-fight. Combat yards are also kept as their own total.
--
-- Saved in AdventureForeverPedometerDB.characters[name-realm]. It stays on your computer.

local _, P = ...

local TICK = 0.5               -- seconds between samples
local MAX_STEP_SPEED = 120     -- yards per second; anything faster is a teleport, not travel
local MIN_STEP = 0.05          -- yards; less is standing still
local YARDS_PER_STEP = 0.85    -- a walking stride
local RUN_SPEED = 7            -- yards per second, the normal run speed
local COMBAT_MAX_SPEED = 14    -- faster than this in a fight is a charge or leap, not steps

P.YARDS_PER_MILE = 1760

P.KINDS = {
	{ key = "foot",    label = "On foot",      icon = "Interface\\Icons\\Ability_Rogue_Sprint" },
	{ key = "mounted", label = "Mounted",      icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
	{ key = "flying",  label = "Flying",       icon = "Interface\\Icons\\Ability_Mount_Gryphon_01" },
	{ key = "swim",    label = "Swimming",     icon = "Interface\\Icons\\Ability_Druid_AquaticForm" },
	{ key = "taxi",    label = "Flight paths", icon = "Interface\\Icons\\Ability_Mount_Wyvern_01" },
}

local function newDistance()
	return { foot = 0, mounted = 0, flying = 0, swim = 0, taxi = 0 }
end

local function newSession()
	return { distance = newDistance(), combat = 0, started = time() }
end

------------------------------------------------------------------------
-- Numbers for people
------------------------------------------------------------------------

-- 1234567 -> "1,234,567"
function P.Commas(n)
	local s = tostring(math.floor(n or 0))
	while true do
		local out, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = out
		if k == 0 then return s end
	end
end

-- A distance for people: "84 yards", "2.35 miles", "31.0 miles".
function P.Distance(yards)
	local m = (yards or 0) / P.YARDS_PER_MILE
	if m < 0.1 then return string.format("%d yards", math.floor(yards or 0)) end
	return string.format(m < 10 and "%.2f miles" or "%.1f miles", m)
end

function P.StepsFrom(yards)
	return math.floor((yards or 0) / YARDS_PER_STEP)
end

-- All the yards in a distance table, every way of traveling added up.
function P.TotalYards(distance)
	local total = 0
	for _, yards in pairs(distance or {}) do total = total + yards end
	return total
end

------------------------------------------------------------------------
-- Records
------------------------------------------------------------------------

-- The record for a character key ("Name-Realm"), created if needed.
function P:GetRecord(key)
	local rec = self.db.characters[key]
	if not rec then
		rec = { distance = newDistance(), combat = 0, session = newSession(), name = key }
		self.db.characters[key] = rec
	end
	rec.distance = rec.distance or newDistance()
	rec.combat = rec.combat or 0
	rec.session = rec.session or newSession()
	return rec
end

local function characterKey()
	local name = P:Readable(UnitName("player"))
	local realm = GetRealmName and P:Readable(GetRealmName())
	if type(name) ~= "string" then return nil end
	return realm and (name .. "-" .. realm) or name
end

-- This character's record (nil before login).
function P:Mine()
	if not self.db then return nil end
	local key = characterKey()
	if not key then return nil end
	local rec = self:GetRecord(key)
	rec.class = rec.class or select(2, UnitClass("player"))
	return rec
end

-- Every character added together.
function P:Totals()
	local total = { distance = newDistance(), combat = 0 }
	for _, rec in pairs(self.db.characters) do
		for kind, yards in pairs(rec.distance or {}) do
			total.distance[kind] = (total.distance[kind] or 0) + yards
		end
		total.combat = total.combat + (rec.combat or 0)
	end
	return total
end

-- Adds travel to a record: all time, and this session.
function P.AddTravel(rec, kind, yards, inCombat)
	rec.session = rec.session or newSession()
	for _, t in ipairs({ rec, rec.session }) do
		t.distance[kind] = (t.distance[kind] or 0) + yards
		if inCombat then t.combat = (t.combat or 0) + yards end
	end
end

------------------------------------------------------------------------
-- Measuring
------------------------------------------------------------------------

local ticker, lastTick
local moving = false
local inCombat = false
local lastPace = RUN_SPEED     -- your last trustworthy speed, for when a fight hides it

-- How many yards per second to count, given the raw speed (nil when the game hides it) and
-- s = { combat, airborne, moving, lastPace }. Outside combat the speed is used as is. In a
-- fight:
--   * a hidden speed counts as your last normal pace while you're moving (you're still
--     running, we just can't see how fast);
--   * speed is capped at COMBAT_MAX_SPEED, so a charge or leap counts like running, not
--     like a 40-yard stride;
--   * in the air (knockbacks, leaps, disengages) only steering at your normal pace counts,
--     and nothing counts if you aren't pressing a movement key.
function P.Pace(speed, s)
	if not s.combat then return speed or 0 end
	local pace = s.lastPace or RUN_SPEED
	if speed == nil then return s.moving and pace or 0 end
	if s.airborne then return s.moving and math.min(speed, pace) or 0 end
	return math.min(speed, COMBAT_MAX_SPEED)
end

-- Yards moved between two positions ({ x, y, z, map }) over dt seconds, or nil when the
-- move doesn't count: a different map (loading screen, portal), a bad interval, or a jump
-- too fast to be travel (hearthstone, summons).
function P.Step(prev, cur, dt)
	if not prev or not cur or prev.map ~= cur.map or not dt or dt <= 0 or dt > 5 then return nil end
	local dx, dy, dz = cur.x - prev.x, cur.y - prev.y, (cur.z or 0) - (prev.z or 0)
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < MIN_STEP then return 0 end
	if d / dt > MAX_STEP_SPEED then return nil end
	return d
end

-- Your position in yards, or nil where the game hides it (dungeons, raids).
local function readPosition()
	if not UnitPosition then return nil end
	local y, x, z, map = UnitPosition("player")
	y, x, z, map = P:Readable(y), P:Readable(x), P:Readable(z), P:Readable(map)
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return { x = x, y = y, z = type(z) == "number" and z or 0, map = map }
end

local lastPos

local function travelKind()
	if P:Readable(UnitOnTaxi("player")) then return "taxi" end
	if IsSwimming and P:Readable(IsSwimming()) then return "swim" end
	if IsFlying and P:Readable(IsFlying()) then return "flying" end
	if P:Readable(IsMounted()) then return "mounted" end
	return "foot"
end

local function stopTicker()
	if ticker then ticker:Cancel() end
	ticker = nil
end

local function sample()
	local now = GetTime()
	local dt = now - (lastTick or now)
	lastTick = now
	local onTaxi = P:Readable(UnitOnTaxi("player"))
	local airborne = IsFalling and P:Readable(IsFalling()) == true
	local pos = readPosition()

	-- Measured distance where we have a position; the reported speed elsewhere.
	local speed
	if pos then
		local step = P.Step(lastPos, pos, dt)
		speed = step and dt > 0 and step / dt or 0
	else
		speed = P:Readable(GetUnitSpeed("player"))
		if type(speed) ~= "number" then speed = nil end
	end
	lastPos = pos

	if speed and speed > 0 and not airborne and not onTaxi and (not inCombat or speed <= COMBAT_MAX_SPEED) then
		lastPace = speed
	end
	local pace = P.Pace(speed, { combat = inCombat, airborne = airborne, moving = moving, lastPace = lastPace })
	if pace > 0 and dt > 0 and dt < 5 then
		local rec = P:Mine()
		if rec then
			P.AddTravel(rec, travelKind(), pace * dt, inCombat)
			if P.UpdateBadge then P:UpdateBadge() end
			if P.RefreshWindow then P:RefreshWindow() end
		end
	elseif not pos and not moving and not onTaxi and not inCombat then
		stopTicker() -- in a dungeon and standing still: wait for the next move
	end
end

-- What the pedometer sees right now (/pedometer status), for checking it in game.
function P:Status()
	local pos = readPosition()
	local speed = self:Readable(GetUnitSpeed("player"))
	return {
		mode = pos and "position" or "speed",
		ticking = ticker ~= nil,
		kind = travelKind(),
		speed = type(speed) == "number" and speed or nil,
		onTaxi = self:Readable(UnitOnTaxi("player")) and true or false,
		swimming = IsSwimming and self:Readable(IsSwimming()) and true or false,
		position = pos,
	}
end

local function startTicker()
	if ticker then return end
	lastTick = GetTime()
	ticker = C_Timer.NewTicker(TICK, sample)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local handlers = {
	PLAYER_ENTERING_WORLD = function(isInitialLogin)
		-- A fresh login starts a new session; a /reload or loading screen doesn't.
		local rec = P:Mine()
		if rec and isInitialLogin then rec.session = newSession() end
		-- A loading screen moves you without traveling. In the open world the ticker runs
		-- all the time (one position check per tick), so swims and flights always count.
		lastPos = nil
		startTicker()
	end,
	PLAYER_STARTED_MOVING = function() moving = true; startTicker() end,
	PLAYER_STOPPED_MOVING = function() moving = false end,
	-- In a fight, keep sampling: the movement events can lag behind strafing and dodging.
	PLAYER_REGEN_DISABLED = function() inCombat = true; startTicker() end,
	PLAYER_REGEN_ENABLED = function() inCombat = false end,
	-- Flight paths take control away instead of firing the movement events.
	PLAYER_CONTROL_LOST = function() C_Timer.After(1, function() if P:Readable(UnitOnTaxi("player")) then startTicker() end end) end,
	PLAYER_CONTROL_GAINED = startTicker,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event, ...)
	if not P.db then return end
	local ok, err = pcall(handlers[event], ...)
	if not ok and P.debug then P:Print("Error in %s: %s", event, tostring(err)) end
end)
