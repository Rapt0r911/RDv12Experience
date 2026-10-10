-- ============================================================================
-- V12 RAPTOR DOUGLAS 911 -- DEV SIDE LOADER
-- Folder: mods/V12_DevLoader/
-- Purpose: Test new modules in isolation before wiring into main mod.
--
-- HOW TO USE:
-- 1. Put your test module in mods/V12_DevLoader/modules/
-- 2. Change TEST_MODULE_NAME below to match
-- 3. Test in game -- main mod is untouched
-- 4. When confirmed working, copy to main mod and add one require line
--
-- This loader registers separately with 0-Engine as "V12_DevLoader"
-- It has NO access to main mod state -- fully isolated
-- ============================================================================

local eng = nil
local function getEng()
    if not eng then eng = GetMod("0-Engine") end
    return eng
end

-- ============================================================================
-- LOAD TARGET -- change this to test different modules
-- ============================================================================
local TEST_MODULE_NAME = "v12_systems_check"  -- loads bridgeSender + wraith_core + wraith_bridge
local testModule = nil

local ok, result = pcall(require, "modules/" .. TEST_MODULE_NAME)
if ok then
    testModule = result
    print("[V12 DevLoader] Loaded: " .. TEST_MODULE_NAME)
else
    print("[V12 DevLoader] FAILED to load: " .. TEST_MODULE_NAME)
    print("[V12 DevLoader] Error: " .. tostring(result))
end

-- ============================================================================
-- MINIMAL STATE -- only what test modules need
-- ============================================================================
local devState = {
    pulse      = 0.0,
    inVehicle  = false,
    speed      = 0.0,
    raceMode   = 0,
}

-- ============================================================================
-- EVENTS
-- ============================================================================
registerForEvent("onInit", function()
    local e = getEng()
    if not e then
        print("[V12 DevLoader] 0-Engine not found -- some features unavailable.")
        return
    end
    e.Register("V12_DevLoader")
    e.WhenReady(function()
        print("[V12 DevLoader] 0-Engine ready.")
        if testModule and testModule.init then
            pcall(function() testModule.init(e) end)
            print("[V12 DevLoader] Module init called.")
        end
    end)
end)

registerForEvent("onUpdate", function(dt)
    devState.pulse = devState.pulse + dt

    local player = Game.GetPlayer()
    if player then
        local vehicle = Game.GetMountedVehicle(player)
        devState.inVehicle = (vehicle ~= nil)
        if vehicle then
            pcall(function()
                local bb   = vehicle:GetBlackboard()
                local defs = Game.GetAllBlackboardDefs()
                if bb and defs then
                    devState.speed = bb:GetFloat(defs.Vehicle.SpeedValue) or 0
                end
            end)
        else
            devState.speed = 0.0
        end
    end

    if testModule and testModule.update then
        pcall(function() testModule.update(dt, devState) end)
    end
end)

registerForEvent("onShutdown", function()
    if testModule and testModule.shutdown then
        pcall(function() testModule.shutdown() end)
    end
    print("[V12 DevLoader] Shutdown.")
end)
