-- ============================================================================
-- MANUAL TRANSMISSION V12 -- modules/gearbox.lua
-- Real gearbox engine: SetLock, ForceGameShift, upshift, downshift
-- 0-Engine replaces Cron -- eng resolved lazily after CET is ready
-- ============================================================================

local utils = require("modules/utils")

-- Green mode shift diagnostics -- mirrors Red's red_debug.txt pattern
local function greenLog(line)
    pcall(function()
        local f = io.open("green_debug.txt", "a")
        if f then
            f:write(os.date("%H:%M:%S") .. "  " .. tostring(line) .. "\n")
            f:close()
        end
    end)
end

-- GetMod is not available at require() time, resolve lazily on first use
local eng = nil
local function getEng()
    if not eng then eng = GetMod("0-Engine") end
    return eng
end

local Gearbox      = {}
local bbVehicleDef = nil

-- FIX 2026-08-04 (E): resolve the blackboard def lazily, not once at init.
-- Gearbox.initialize() is called from init.lua inside eng.WhenReady, which
-- fires BEFORE the blackboard system is populated, so allDefs.Vehicle came
-- back nil and this local stayed nil for the whole session. Assigning nil
-- does not throw, so ForceGameShift and ForceGameSync below silently did
-- NOTHING: the mod tracked gears internally and drove the gear display, but
-- never wrote the gear to the vehicle. The native transmission stayed in
-- whatever ratio it liked.
-- That is exactly "no power in low gears" plus "GUI does not match the gear".
-- Note this is a SECOND copy of the same bug fixed in init.lua -- each file
-- has its own module-local bbVehicleDef. Check every file that declares one.
local function getBBDef()
    if not bbVehicleDef then
        local ok, defs = pcall(Game.GetAllBlackboardDefs)
        if ok and defs then bbVehicleDef = defs.Vehicle end
    end
    return bbVehicleDef
end

function Gearbox.initialize()
    getBBDef()
end

function Gearbox.SetLock(state, shouldLock)
    if state.isLocked ~= shouldLock then
        GameOptions.Toggle("Vehicle", "BlockChangeGear", shouldLock and "true" or "false")
        state.isLocked = shouldLock
    end
end

function Gearbox.ForceGameShift(state, vehicle, targetGear)
    local vehicleBB = state.vehicleBlackboard
    local def       = getBBDef()
    if vehicleBB and def then
        vehicleBB:SetInt(def.GearValue, targetGear, true)
    end
end

function Gearbox.ForceGameSync(state, vehicle)
    local vehicleBB = state.vehicleBlackboard
    local def       = getBBDef()
    if vehicleBB and def then
        vehicleBB:SignalInt(def.GearValue)
    end
end

function Gearbox.GetBestGearForSpeed(state, currentSpeed)
    if not state.vehicleStats or not state.vehicleStats.gears then return 1 end
    local gears    = state.vehicleStats.gears
    local speedAbs = math.abs(currentSpeed)
    local count    = #gears
    for i = 1, count do
        if speedAbs <= gears[i].maxSpeed then return i end
    end
    return count
end

-- Read shift delay modifier from gearboxFeel if available
local function shiftDelayMod()
    local okFeel, gearboxFeel = pcall(require, "modules/gearboxFeel")
    if okFeel and gearboxFeel and gearboxFeel.getTelemetry then
        local ok, tel = pcall(gearboxFeel.getTelemetry)
        if ok and tel and tel.shiftDelayModifier then
            return tel.shiftDelayModifier
        end
    end
    return 1.0
end

function Gearbox.upshift(state, settings, inputManager)
    if not state.inVehicle or not state.isManualMode or state.shifting then
        greenLog(string.format("UP blocked: inVehicle=%s isManualMode=%s shifting=%s cur=%s",
            tostring(state.inVehicle), tostring(state.isManualMode),
            tostring(state.shifting), tostring(state.currentGear)))
        return
    end

    local vehicle = state.playerVehicle
    local isBike  = vehicle:IsA(CName("vehicleBikeBaseObject"))
    local targetGear = state.currentGear + 1

    if isBike and (state.currentGear == -1 or state.currentGear == 0) then
        targetGear = 1
    elseif not isBike and state.currentGear == 0 then
        targetGear = -1
    end

    local clutchIn = not settings.mt_require_clutch
        or state.digitalHold
        or (state.clutchEngagementRamp and state.clutchEngagementRamp < 0.3)
    if not clutchIn and state.vehicleStats and state.vehicleStats.gears then
        local gearData = state.vehicleStats.gears[targetGear]
        if gearData and gearData.minSpeed
        and math.abs(state.speed) < (gearData.minSpeed * 0.45) then
            greenLog(string.format("UP minSpeed blocked: cur=%s target=%s spd=%.1f gate=%.1f",
                tostring(state.currentGear), tostring(targetGear),
                math.abs(state.speed), gearData.minSpeed * 0.45))
            return
        end
    end

    if state.currentGear == -1 and not isBike then
        targetGear = Gearbox.GetBestGearForSpeed(state, state.speed)
        if targetGear < 1 then targetGear = 1 end
    end

    if state.vehicleStats and state.vehicleStats.gears and targetGear > #state.vehicleStats.gears then
        return
    end

    if targetGear ~= state.currentGear then
        greenLog(string.format("UP accepted: cur=%s target=%s spd=%.1f gearChangeTime=%.3f raceMode=%s",
            tostring(state.currentGear), tostring(targetGear), math.abs(state.speed or 0),
            (state.vehicleStats and state.vehicleStats.gearChangeTime) or 0.2,
            tostring(state.raceMode)))
        state.persistentNeutralUI = false
        Gearbox.SetLock(state, false)
        state.shifting   = true
        state.targetGear = targetGear

        local changeTime = 0.2
        if state.vehicleStats and state.vehicleStats.gearChangeTime then
            changeTime = state.vehicleStats.gearChangeTime
        end
        -- Enforce minimum settle so key-repeat can't fire continuously while held
        state.shiftTimeout = math.max(0.30, changeTime * shiftDelayMod())

        local isNeutralTarget = (targetGear == -1)
        Gearbox.ForceGameShift(state, vehicle, targetGear)
        Gearbox.ForceGameSync(state, vehicle)
        if state.raceMode == 0 then state.currentGear = targetGear end
        pcall(function()
            Game.MtSetRecoveryGear(targetGear)
            if isNeutralTarget then Game.MtClutchDisengage()
            else                     Game.MtClutchEngage()  end
        end)
    end
end

function Gearbox.downshift(state, settings, inputManager)
    if not state.inVehicle or not state.isManualMode or state.shifting then return end

    local vehicle = state.playerVehicle
    if not vehicle then return end

    local isBike     = vehicle:IsA(CName("vehicleBikeBaseObject"))
    local targetGear = state.currentGear - 1

    -- Down from 1st stays in 1st. Neutral lives on comma (mt_perpetual_neutral_key).
    -- Down from Neutral goes to Reverse. Down from Reverse does nothing.
    if     state.currentGear == 1  then
        greenLog("DOWN blocked: already in 1st")
        return
    elseif state.currentGear == -1 then
        greenLog("DOWN blocked: gear unknown (-1), ignoring")
        return
    elseif state.currentGear == 0  then return
    end

    greenLog(string.format("DOWN: cur=%s target=%s spd=%.1f",
        tostring(state.currentGear), tostring(targetGear), math.abs(state.speed or 0)))

    local isStandardGear = (targetGear >= 1)

    if isStandardGear or targetGear == -1 or targetGear == 0 then
        local safeTargetSpeed = 3.0
        local hasGearData     = state.vehicleStats and state.vehicleStats.gears and state.vehicleStats.gears[targetGear]

        if isStandardGear and hasGearData then
            local sm = 1.0
            if isBike then
                if     targetGear == 1 then sm = 0.74
                elseif targetGear == 2 then sm = 0.80
                elseif targetGear == 3 then sm = 0.84
                elseif targetGear == 4 then sm = 0.88
                elseif targetGear == 5 then sm = 0.88
                elseif targetGear >= 6 then sm = 0.96 end
            else
                if     targetGear == 1 then sm = 0.74
                elseif targetGear == 2 then sm = 0.80
                elseif targetGear == 3 then sm = 0.84
                elseif targetGear == 4 then sm = 0.88
                elseif targetGear == 5 then sm = 0.92
                elseif targetGear == 6 then sm = 0.96
                elseif targetGear >= 7 then sm = 1.00 end
            end
            safeTargetSpeed = state.vehicleStats.gears[targetGear].maxSpeed * sm
        elseif not hasGearData then
            safeTargetSpeed = 999.0
        end

        state.targetGear = targetGear

        local changeTime = 0.2
        if state.vehicleStats and state.vehicleStats.gearChangeTime then
            changeTime = state.vehicleStats.gearChangeTime
        end
        local delayedChange = math.max(0.30, changeTime * shiftDelayMod())

        -- 1.15 tolerance: the gear records are now correctly aligned, so
        -- safeTargetSpeed is the REAL max for the target gear rather than the
        -- next gear up. Without headroom almost every downshift diverts into
        -- the brake-and-wait path and feels like it was refused.
        if state.speed <= (safeTargetSpeed * 1.15) or (state.currentGear == -1 and targetGear == 0) then
            Gearbox.SetLock(state, false)
            state.shifting     = true
            state.shiftTimeout = delayedChange

            local isNeutralTarget = (targetGear == -1)
            pcall(function() Game.MtSetThrottle(0.0) end)
            Gearbox.ForceGameShift(state, vehicle, targetGear)
            Gearbox.ForceGameSync(state, vehicle)
            if state.raceMode == 0 then state.currentGear = targetGear end
            pcall(function()
                Game.MtSetRecoveryGear(targetGear)
                if isNeutralTarget then Game.MtClutchDisengage()
                else                     Game.MtClutchEngage()  end
                Game.MtSetThrottle(1.0)
            end)
            return
        end

        local speedDelta      = state.speed - safeTargetSpeed
        local gearData        = utils.getVehicleGearData()
        local decelerationRate= utils.calculateBrakingDeceleration(gearData)
        local brakeDuration   = 0.0
        if decelerationRate and decelerationRate > 0.001 and speedDelta > 0 then
            brakeDuration = speedDelta / decelerationRate
        end

        pcall(function()
            Game.MtClutchDisengage()
            Game.MtSetThrottle(0.0)
        end)

        vehicle:ForceBrakesFor(3.0)
        state.shifting     = true
        state.shiftTimeout = brakeDuration + delayedChange

        local timeElapsed   = 0.0
        local failsafe      = brakeDuration + 0.5
        local speedMonitor

        speedMonitor = getEng().SetInterval(0.016, function()
            timeElapsed = timeElapsed + 0.016
            if state.speed <= safeTargetSpeed or timeElapsed >= failsafe then
                Gearbox.SetLock(state, false)
                state.shiftTimeout = delayedChange
                vehicle:ForceBrakesFor(0.0)

                local isNeutralTarget = (targetGear == -1)
                Gearbox.ForceGameShift(state, vehicle, targetGear)
                Gearbox.ForceGameSync(state, vehicle)
                if state.raceMode == 0 then state.currentGear = targetGear end
                pcall(function()
                    Game.MtSetRecoveryGear(targetGear)
                    if isNeutralTarget then Game.MtClutchDisengage()
                    else                     Game.MtClutchEngage()  end
                    Game.MtSetThrottle(1.0)
                end)
                getEng().ClearTimer(speedMonitor)
            end
        end)
    end
end

return Gearbox