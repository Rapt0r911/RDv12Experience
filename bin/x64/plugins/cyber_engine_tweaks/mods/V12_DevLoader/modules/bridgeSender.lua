-- ============================================================================
-- V12 RAPTOR DOUGLAS 911 -- modules/bridgeSender.lua
-- Game State Bridge: writes live game data to a JSON file every 2 seconds.
-- bridge.py (Python side) watches this file and feeds Skippy's context.
--
-- Usage in DevLoader:  TEST_MODULE_NAME = "bridgeSender"
-- Usage in main mod:   local Bridge = require("modules/bridgeSender")
--                      Bridge.init(eng)  -- in WhenReady block
--                      Bridge.update(dt, { speed=..., raceMode=... })  -- in onUpdate
--
-- Data written: nerve, speed, phase, mode, stress, adrenaline, district
-- Output file:  F:/Voice bridges to Gr8ness/game_state.json
--
-- Pure ASCII. Lua 5.1.
-- ============================================================================

local BridgeSender = {}

local BRIDGE_URL    = "http://127.0.0.1:5000/game_state"
local SEND_INTERVAL = 2.0
local _bridgeTimer  = nil

local _eng        = nil
local _speed      = 0.0
local _raceMode   = 0
local _inVehicle  = false
local _stress     = 0.0
local _adrenaline = 0.0

local function readNerve()
    local nerve = 100.0
    pcall(function()
        local dfs = Game.GetScriptableSystemsContainer():Get("DarkFuture.Needs.DFNerveSystem")
        if dfs then nerve = dfs:GetNeedValue() or 100.0 end
    end)
    return nerve
end

local function nerveToPhase(nerve)
    if     nerve >= 70 then return 1
    elseif nerve >= 50 then return 2
    elseif nerve >= 30 then return 3
    elseif nerve >= 10 then return 4
    elseif nerve >   0 then return 5
    else                    return 6
    end
end

local function modeLabel(raceMode)
    if     raceMode == 1 then return "blue"
    elseif raceMode == 2 then return "red"
    else                      return "green"
    end
end

local function writeState()
    local nerve = readNerve()
    local phase = nerveToPhase(nerve)
    local mode  = modeLabel(_raceMode)
    local speed = math.abs(_speed)

    local json = string.format(
        '{"nerve":%.1f,"speed":%.1f,"district":"%s","mode":"%s","kills":%d,"wanted":%d,"phase":%d,"stress":%.1f,"adrenaline":%.1f}',
        nerve, speed, "unknown", mode, 0, 0, phase, _stress, _adrenaline
    )

    -- CET sandboxes io.open writes -- use curl to POST directly to bridge.py
    pcall(function()
        local escaped = json:gsub('"', '\\"')
        local cmd = 'curl -s -X POST ' .. BRIDGE_URL
                 .. ' -H "Content-Type: application/json"'
                 .. ' -d "' .. escaped .. '" >NUL 2>&1'
        local h = io.popen(cmd)
        if h then h:close() end
    end)
end

function BridgeSender.update(dt, params)
    params     = params or {}
    _speed     = params.speed      or 0.0
    _inVehicle = params.inVehicle  or false
    _raceMode  = params.raceMode   or 0
    _stress    = params.stress     or 0.0
    _adrenaline= params.adrenaline or 0.0
end

function BridgeSender.init(engine)
    _eng = engine
    if _eng and _eng.SetInterval then
        -- POST initial state immediately so bridge.py has context on load
        pcall(writeState)
        print("[BridgeSender] Initial state posted to bridge.")

        _bridgeTimer = _eng.SetInterval(SEND_INTERVAL, function()
            pcall(writeState)
        end)
        print("[BridgeSender] Initialized.")
        print("[BridgeSender]   POST -> " .. BRIDGE_URL)
        print("[BridgeSender]   Every " .. SEND_INTERVAL .. "s")
    else
        print("[BridgeSender] WARNING: No 0-Engine handle -- interval not running.")
    end
end

function BridgeSender.shutdown()
    if _eng and _bridgeTimer then
        pcall(function() _eng.ClearTimer(_bridgeTimer) end)
        _bridgeTimer = nil
    end
    -- No file cleanup needed -- bridge.py holds state in memory, resets on restart
    print("[BridgeSender] Shutdown.")
end

return BridgeSender
