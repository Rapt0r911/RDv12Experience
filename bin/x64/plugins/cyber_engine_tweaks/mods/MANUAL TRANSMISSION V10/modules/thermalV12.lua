-- ============================================================================
-- MANUAL TRANSMISSION V12 RAPTOR EAGLE 911 -- modules/thermalV12.lua
-- V12 Thermal Immersion Framework
-- Systems: Stress/Nerves, Adrenaline, Clutch Heat, Stall Detection,
--          DUI tracking, Weather multiplier, Survival Run scoring,
--          Throttle Inertia (ported from retired gearboxFeel.lua)
-- Runtime: 0-Engine (lazy-resolved). Publishes all state to eng.SetData
--          so future mods (Whisper AI, district awareness) can read it.
-- ============================================================================

local ThermalV12 = {}

-- ============================================================================
-- CONFIGURATION  --  all thresholds have defaults, exposed via NativeSettings
-- ============================================================================
ThermalV12.config = {
    -- Speed threshold for "in the zone" calm
    speedZoneFloor      = 130.0,   -- km/h minimum to trigger zone
    speedZoneTopPct     = 0.65,    -- luxury cars: 65% of top speed if higher

    -- Stress / Nerves
    stressDecayRate     = 1.5,     -- points/sec calm driving bleeds stress
    stressBadShift      = 8.0,     -- stress spike per bad shift
    stressNearMiss      = 12.0,    -- stress spike per near miss
    stressAccident      = 25.0,    -- stress spike per collision
    stressSpeedZone     = 3.0,     -- stress drain bonus/sec at speed zone
    stressPedHit        = 40.0,    -- stress spike hitting pedestrian

    -- Adrenaline
    adrenalineBuildRate = 2.0,     -- points/sec above speed threshold
    adrenalineDecayRate = 1.0,     -- points/sec below threshold
    adrenalineNearMiss  = 6.0,     -- spike per near miss (survived = thrill)
    adrenalineMax       = 100.0,

    -- Clutch heat (Red mode)
    clutchHeatRate      = 18.0,    -- CC/sec riding clutch in powerband
    clutchCoolRate      = 5.0,     -- CC/sec cooling
    clutchHeatThreshold = 85.0,    -- CC before penalty
    clutchMaxTemp       = 125.0,   -- CC hard cap

    -- Throttle inertia (ported from gearboxFeel.lua 2026-08-07)
    flywheelInertia     = 0.15,    -- rotational mass feel (0.05=light, 0.25=heavy)
    throttleSmoothing   = 7.5,     -- rate of throttle input transition (higher=snappier)

    -- Weather multipliers
    rainMultipliers = {
        ["24h_weather_clear"]        = 0.0,
        ["24h_weather_cloudy"]       = 0.0,
        ["24h_weather_light_rain"]   = 0.3,
        ["24h_weather_rain"]         = 0.6,
        ["24h_weather_heavy_rain"]   = 0.85,
        ["24h_weather_storm"]        = 1.0,
        ["24h_weather_downpour"]     = 1.0,
        ["24h_weather_toxic_rain"]   = 1.0,
        -- Nova City states
        ["nc_drizzle"]               = 0.25,
        ["nc_drizzle_light"]         = 0.15,
        ["nc_rain"]                  = 0.6,
        ["nc_heavy_rain"]            = 0.85,
        ["nc_downpour"]              = 1.0,
        ["nc_rain_storm"]            = 1.0,
        ["nc_fog_rain"]              = 0.5,
    },

    -- DUI system
    duiDrinkBonusCutoff = 3,       -- drinks before BODrunk kicks in
    duiStressMult       = 1.4,     -- stress multiplier while drunk
    duiAdrenalineMult   = 1.2,     -- adrenaline mult while drunk (liquid courage)
    duiPedHitMult       = 2.0,     -- extra humanity penalty while drunk
    duiDebuffBaseTime   = 120.0,   -- seconds driving restricted after bad DUI run

    -- Survival Run
    survivalPedThreshold = 0,      -- max peds hit for clean run payoff
    survivalDmgThreshold = 0.35,   -- max vehicle damage ratio for payoff

    -- Tick rates
    thermalTickRate     = 0.5,     -- thermal state update interval (sec)
    survivalTickRate    = 2.0,     -- survival run metric collection interval
}

-- ============================================================================
-- STATE
-- ============================================================================
ThermalV12.state = {
    -- Stress / Nerves (0-100)
    stress              = 20.0,
    stressFlash         = 0.0,

    -- Adrenaline (0-100)
    adrenaline          = 0.0,

    -- Clutch heat
    clutchTemp          = 20.0,
    clutchOverheated    = false,

    -- Throttle inertia (ported from gearboxFeel.lua 2026-08-07)
    smoothedThrottle    = 0.0,
    targetThrottle      = 0.0,

    -- Weather
    currentWeather      = "24h_weather_clear",
    rainMultiplier      = 0.0,

    -- DUI tracking
    isDrunk             = false,
    drinkCount          = 0,
    isBODrunk           = false,    -- cutoff breached
    duiRecord = {
        active          = false,
        damageDealt     = 0.0,
        pedestrianHits  = 0,
        topSpeed        = 0.0,
        avgSpeedSum     = 0.0,
        avgSpeedTicks   = 0,
        timeInRain      = 0.0,
        debuffTimer     = 0.0,      -- remaining restriction time
    },

    -- Survival Run
    survivalRun = {
        active          = false,
        startTime       = 0.0,
        topSpeed        = 0.0,
        avgSpeedSum     = 0.0,
        avgSpeedTicks   = 0,
        closeCalls      = 0,
        pedHits         = 0,
        damageRatio     = 0.0,
        timeInRain      = 0.0,
        rainMultAtStart = 0.0,
    },

    -- Internal timers
    thermalTimer        = 0.0,
    survivalTimer       = 0.0,
    pulse               = 0.0,     -- running time for flash animations
}

-- ============================================================================
-- 0-ENGINE LAZY RESOLVER
-- ============================================================================
local eng = nil
local function getEng()
    if not eng then eng = GetMod("0-Engine") end
    return eng
end

-- ============================================================================
-- SHARED DATA BUS  --  publishes state so Whisper/AI and other mods can read
-- ============================================================================
local function publishState()
    local e = getEng()
    if not e then return end
    pcall(function()
        e.SetData("V12.stress",         ThermalV12.state.stress)
        e.SetData("V12.adrenaline",     ThermalV12.state.adrenaline)
        e.SetData("V12.clutchTemp",     ThermalV12.state.clutchTemp)
        e.SetData("V12.rainMult",       ThermalV12.state.rainMultiplier)
        e.SetData("V12.isDrunk",        ThermalV12.state.isDrunk)
        e.SetData("V12.isBODrunk",      ThermalV12.state.isBODrunk)
        e.SetData("V12.duiDebuff",      ThermalV12.state.duiRecord.debuffTimer)
        e.SetData("V12.survivalActive", ThermalV12.state.survivalRun.active)
        e.SetData("V12.smoothedThrottle", ThermalV12.state.smoothedThrottle)
    end)
end

-- ============================================================================
-- WEATHER QUERY
-- Reads Auto Weather's saved state if live query unavailable.
-- Falls back to "clear" -- system still runs, just no rain multiplier.
-- ============================================================================
local function updateWeather()
    local s = ThermalV12.state
    local found = false

    -- Try live engine query first
    pcall(function()
        local ws = Game.GetWeatherSystem()
        local name = nil
        pcall(function() name = ws:GetWeather() end)
        if not name then pcall(function() name = ws:GetWeatherState() end) end
        if not name then pcall(function() name = ws:GetCurrentPresetName() end) end
        if name and type(name) == "string" and name ~= "" then
            s.currentWeather = name
            found = true
        end
    end)

    if not found then
        pcall(function()
            local e = getEng()
            if e then
                local w = e.GetData("AutoWeather.currentWeather")
                if w and type(w) == "string" then
                    s.currentWeather = w
                    found = true
                end
            end
        end)
    end

    local mult = ThermalV12.config.rainMultipliers[s.currentWeather] or 0.0
    s.rainMultiplier = mult
end

-- ============================================================================
-- DRUNK STATUS QUERY
-- ============================================================================
local function updateDrunkStatus()
    local s = ThermalV12.state
    local found = false

    pcall(function()
        local player = Game.GetPlayer()
        if not player then return end

        local ses = Game.GetStatusEffectSystem()
        if ses then
            local eid = player:GetEntityID()
            local drunk = false
            local ok1 = pcall(function()
                drunk = ses:HasStatusEffect(eid, CName.new("BaseFunctions.Drunk"))
            end)
            if not ok1 then
                pcall(function()
                    drunk = ses:HasStatusEffectWithTag(eid, CName.new("Drunk"))
                end)
            end
            if drunk ~= nil then
                s.isDrunk = drunk
                found = true
            end
        end
    end)

    if s.isDrunk and s.drinkCount >= ThermalV12.config.duiDrinkBonusCutoff then
        s.isBODrunk = true
    else
        s.isBODrunk = false
    end
end

-- ============================================================================
-- STRESS UPDATE
-- ============================================================================
local function updateStress(dt, vehicleSpeed, isInZone)
    local s    = ThermalV12.state
    local cfg  = ThermalV12.config
    local rain = s.rainMultiplier

    local decayRate = cfg.stressDecayRate
    if isInZone then
        decayRate = decayRate + cfg.stressSpeedZone * (1.0 + rain * 0.5)
    end

    if rain > 0 then
        s.stress = s.stress + (rain * 0.8 * dt)
    end

    s.stress = math.max(0.0, math.min(100.0, s.stress - (decayRate * dt)))

    if s.stressFlash > 0 then
        s.stressFlash = s.stressFlash - dt
    end
end

-- ============================================================================
-- ADRENALINE UPDATE
-- ============================================================================
local function updateAdrenaline(dt, vehicleSpeed, isInZone, topSpeed)
    local s   = ThermalV12.state
    local cfg = ThermalV12.config

    local threshold = cfg.speedZoneFloor
    if topSpeed and topSpeed > 0 then
        local pctThreshold = topSpeed * cfg.speedZoneTopPct
        threshold = math.max(cfg.speedZoneFloor, pctThreshold)
    end

    if isInZone and math.abs(vehicleSpeed) >= threshold then
        local buildMult = 1.0
        if s.isDrunk and not s.isBODrunk then
            buildMult = cfg.duiAdrenalineMult
        elseif s.isBODrunk then
            buildMult = 0.3
        end
        s.adrenaline = math.min(cfg.adrenalineMax,
            s.adrenaline + cfg.adrenalineBuildRate * buildMult * dt)
    else
        s.adrenaline = math.max(0.0,
            s.adrenaline - cfg.adrenalineDecayRate * dt)
    end
end

-- ============================================================================
-- CLUTCH HEAT UPDATE  (Red mode only -- passed from init.lua)
-- ============================================================================
local function updateClutchHeat(dt, isClutchSlipping, currentRPMProxy)
    local s   = ThermalV12.state
    local cfg = ThermalV12.config

    if isClutchSlipping then
        local heatRate = cfg.clutchHeatRate * (1.0 + s.rainMultiplier * 0.2)
        s.clutchTemp = math.min(cfg.clutchMaxTemp,
            s.clutchTemp + heatRate * dt)
    else
        s.clutchTemp = math.max(20.0,
            s.clutchTemp - cfg.clutchCoolRate * dt)
    end

    s.clutchOverheated = (s.clutchTemp >= cfg.clutchHeatThreshold)
end

-- ============================================================================
-- THROTTLE INERTIA  --  ported from retired gearboxFeel.lua 2026-08-07
-- Exponential smoothing to emulate flywheel mass and drivetrain lash.
-- Call from init.lua onUpdate, pass raw throttle (0.0-1.0), get smoothed back.
-- Result also stored in state.smoothedThrottle and published to the bus.
-- ============================================================================
function ThermalV12.updateThrottleInertia(rawThrottle, dt)
    local s   = ThermalV12.state
    local cfg = ThermalV12.config

    s.targetThrottle = rawThrottle

    -- Exponential blend: higher throttleSmoothing = snappier response
    -- flywheelInertia adds rotational mass damping on top
    local blendFactor = 1.0 - math.exp(
        -cfg.throttleSmoothing * dt / (1.0 + cfg.flywheelInertia)
    )
    s.smoothedThrottle = s.smoothedThrottle
        + (s.targetThrottle - s.smoothedThrottle) * blendFactor

    return s.smoothedThrottle
end

-- ============================================================================
-- SURVIVAL RUN -- metric collection tick
-- ============================================================================
local function updateSurvivalRun(dt, vehicleSpeed, inVehicle)
    local s   = ThermalV12.state
    local sr  = s.survivalRun

    if not inVehicle then
        if sr.active then
            ThermalV12.evaluateSurvivalRun()
        end
        return
    end

    if not sr.active then
        sr.active       = true
        sr.startTime    = 0.0
        sr.topSpeed     = 0.0
        sr.avgSpeedSum  = 0.0
        sr.avgSpeedTicks= 0
        sr.closeCalls   = 0
        sr.pedHits      = 0
        sr.damageRatio  = 0.0
        sr.timeInRain   = 0.0
        sr.rainMultAtStart = s.rainMultiplier
    end

    local spd = math.abs(vehicleSpeed)
    if spd > sr.topSpeed then sr.topSpeed = spd end
    sr.avgSpeedSum  = sr.avgSpeedSum + spd
    sr.avgSpeedTicks= sr.avgSpeedTicks + 1

    if s.rainMultiplier > 0 then
        sr.timeInRain = sr.timeInRain + dt
    end
end

-- ============================================================================
-- SURVIVAL RUN EVALUATION  --  called on vehicle exit
-- ============================================================================
function ThermalV12.evaluateSurvivalRun()
    local s   = ThermalV12.state
    local sr  = s.survivalRun
    local cfg = ThermalV12.config

    if not sr.active or sr.avgSpeedTicks == 0 then
        sr.active = false
        return
    end

    sr.active = false
    local avgSpeed = sr.avgSpeedSum / sr.avgSpeedTicks

    local isClean = (sr.pedHits <= cfg.survivalPedThreshold)
               and (sr.damageRatio <= cfg.survivalDmgThreshold)

    local score = avgSpeed
                * (1.0 + sr.timeInRain * 0.01)
                * (1.0 + sr.rainMultAtStart * 0.5)
                * (1.0 + sr.closeCalls * 0.05)

    local duiMult = 1.0
    if s.isDrunk then
        duiMult = 1.0 + (s.drinkCount * 0.25)
    end

    if isClean then
        local adrBoost  = math.min(30.0, score * 0.1)
        local stressDrop= math.min(s.stress, 20.0 + score * 0.05)
        s.adrenaline = math.min(cfg.adrenalineMax, s.adrenaline + adrBoost)
        s.stress     = math.max(0.0, s.stress - stressDrop)
        print(string.format("[V12 Thermal] Clean run! Score: %.0f | Adrenaline +%.1f | Stress -%.1f",
            score, adrBoost, stressDrop))
    else
        local stressBill = math.min(50.0, score * 0.08 * duiMult)
        s.stress = math.min(100.0, s.stress + stressBill)
        if s.isDrunk then
            local debuffAdd = cfg.duiDebuffBaseTime
                            + (sr.pedHits * 120.0)
                            + (sr.damageRatio * 60.0)
            s.duiRecord.debuffTimer = s.duiRecord.debuffTimer + debuffAdd
            s.duiRecord.pedestrianHits = s.duiRecord.pedestrianHits + sr.pedHits
            print(string.format("[V12 Thermal] DUI consequence! Debuff +%.0fs | Stress +%.1f",
                debuffAdd, stressBill))
        end
    end

    publishState()
end

-- ============================================================================
-- PUBLIC EVENT HOOKS  --  called from init.lua on game events
-- ============================================================================

function ThermalV12.onBadShift()
    local s   = ThermalV12.state
    local cfg = ThermalV12.config
    local mult = s.isDrunk and (s.isBODrunk and 0.5 or cfg.duiStressMult) or 1.0
    s.stress = math.min(100.0, s.stress + cfg.stressBadShift * mult
                                        * (1.0 + s.rainMultiplier * 0.3))
    s.stressFlash = 0.4
    publishState()
end

function ThermalV12.onNearMiss()
    local s   = ThermalV12.state
    local cfg = ThermalV12.config
    s.stress    = math.min(100.0, s.stress    + cfg.stressNearMiss
                                              * (1.0 + s.rainMultiplier * 0.5))
    s.adrenaline= math.min(cfg.adrenalineMax, s.adrenaline + cfg.adrenalineNearMiss)
    s.survivalRun.closeCalls = s.survivalRun.closeCalls + 1
    publishState()
end

function ThermalV12.onPedHit()
    local s   = ThermalV12.state
    local cfg = ThermalV12.config
    local mult = s.isDrunk and cfg.duiPedHitMult or 1.0
    s.stress    = math.min(100.0, s.stress + cfg.stressPedHit * mult)
    s.adrenaline= math.max(0.0,   s.adrenaline - 15.0)
    s.survivalRun.pedHits = s.survivalRun.pedHits + 1
    s.stressFlash = 0.8
    publishState()
end

function ThermalV12.onCollision(damageRatio)
    local s   = ThermalV12.state
    local cfg = ThermalV12.config
    local rain = s.rainMultiplier
    s.stress  = math.min(100.0, s.stress + cfg.stressAccident
                                         * (1.0 + rain * 0.6))
    s.survivalRun.damageRatio = math.max(s.survivalRun.damageRatio,
                                         damageRatio or 0.0)
    s.stressFlash = 0.6
    publishState()
end

function ThermalV12.onStall()
    local s = ThermalV12.state
    s.clutchTemp = math.min(ThermalV12.config.clutchMaxTemp,
                            s.clutchTemp + 12.0)
    s.stress     = math.min(100.0, s.stress + 5.0)
    publishState()
end

-- ============================================================================
-- TELEMETRY -- read by init.lua for HUD rendering
-- ============================================================================
function ThermalV12.getTelemetry()
    return ThermalV12.state
end

-- ============================================================================
-- MAIN UPDATE -- called from init.lua onUpdate with deltaTime
-- ============================================================================
function ThermalV12.update(dt, vehicleSpeed, isInVehicle, isClutchSlipping,
                            rpmProxy, topSpeed, raceMode)
    local s   = ThermalV12.state
    local cfg = ThermalV12.config

    s.pulse = s.pulse + dt

    if s.duiRecord.debuffTimer > 0 then
        s.duiRecord.debuffTimer = math.max(0.0,
            s.duiRecord.debuffTimer - dt)
    end

    local spd = math.abs(vehicleSpeed or 0)
    local threshold = cfg.speedZoneFloor
    if topSpeed and topSpeed > 0 then
        threshold = math.max(cfg.speedZoneFloor, topSpeed * cfg.speedZoneTopPct)
    end
    local isInZone = (spd >= threshold)

    s.thermalTimer = s.thermalTimer + dt
    if s.thermalTimer >= cfg.thermalTickRate then
        s.thermalTimer = 0.0
        updateWeather()
        updateDrunkStatus()
        updateClutchHeat(cfg.thermalTickRate, isClutchSlipping, rpmProxy)
        publishState()
    end

    if isInVehicle then
        updateStress(dt, spd, isInZone)
        updateAdrenaline(dt, spd, isInZone, topSpeed)
    end

    s.survivalTimer = s.survivalTimer + dt
    if s.survivalTimer >= cfg.survivalTickRate then
        s.survivalTimer = 0.0
        updateSurvivalRun(cfg.survivalTickRate, spd, isInVehicle)
    end
end

-- ============================================================================
-- INIT
-- ============================================================================
function ThermalV12.init()
    local s = ThermalV12.state
    s.stress            = 20.0
    s.adrenaline        = 0.0
    s.clutchTemp        = 20.0
    s.clutchOverheated  = false
    s.rainMultiplier    = 0.0
    s.isDrunk           = false
    s.isBODrunk         = false
    s.smoothedThrottle  = 0.0
    s.targetThrottle    = 0.0
    s.duiRecord.debuffTimer = 0.0
    s.survivalRun.active    = false
    s.pulse             = 0.0
    s.thermalTimer      = 0.0
    s.survivalTimer     = 0.0
    print("[V12 Thermal] thermalV12.lua initialised.")
end

return ThermalV12