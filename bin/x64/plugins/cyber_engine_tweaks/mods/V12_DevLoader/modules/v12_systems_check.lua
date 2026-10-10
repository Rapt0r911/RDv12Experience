-- ============================================================================
-- V12 RAPTOR DOUGLAS 911 -- SYSTEMS CHECK LOADER
-- modules/v12_systems_check.lua
--
-- Combined test loader. Set TEST_MODULE_NAME = "v12_systems_check" in DevLoader.
-- Brings up all active systems in one pass:
--   bridgeSender  -- game state -> game_state.json -> FileWatcher -> Skippy context
--   wraith_core   -- event bus, DRM, pub/sub
--   wraith_bridge -- event queue -> wraith_events.json -> bridge.py -> response
--
-- Console test commands (paste in CET):
--   local sc = GetMod("V12_DevLoader")  -- not directly, use module refs below
--   WRAITH.emit("skippy_say", { text = "Systems check. All green." })
--   WRAITHBridge.speak("test line", {})
--
-- Check bridge.py terminal for:
--   [FileWatcher]  nerve=...  speed=...  -- bridgeSender confirmed
--   [WRAITH]       event received         -- event bus confirmed
--   [Skippy]       response line          -- full loop confirmed
--
-- Pure ASCII. Lua 5.1.
-- ============================================================================

local SystemsCheck = {}

-- Hold references so they survive require cache
local BridgeSender  = nil
local WRAITH        = nil
local WRAITHBridge  = nil
local _eng          = nil

-- ============================================================================
-- LOAD ALL MODULES
-- pcall each so one failure doesn't kill the rest
-- ============================================================================

local function loadModules()
    local ok, result

    -- Bridge Sender
    ok, result = pcall(require, "modules/bridgeSender")
    if ok then
        BridgeSender = result
        print("[SystemsCheck] bridgeSender loaded.")
    else
        print("[SystemsCheck] FAILED: bridgeSender -- " .. tostring(result))
    end

    -- WRAITH Core
    ok, result = pcall(require, "modules/wraith_core")
    if ok then
        WRAITH = result
        print("[SystemsCheck] wraith_core loaded.")
    else
        print("[SystemsCheck] FAILED: wraith_core -- " .. tostring(result))
    end

    -- WRAITH Bridge
    ok, result = pcall(require, "modules/wraith_bridge")
    if ok then
        WRAITHBridge = result
        print("[SystemsCheck] wraith_bridge loaded.")
    else
        print("[SystemsCheck] FAILED: wraith_bridge -- " .. tostring(result))
    end
end

-- ============================================================================
-- INIT -- called by DevLoader WhenReady block
-- ============================================================================

function SystemsCheck.init(engine)
    _eng = engine

    -- BridgeSender -- game state writer
    if BridgeSender then
        pcall(function() BridgeSender.init(_eng) end)
        print("[SystemsCheck] BridgeSender init done.")
    end

    -- WRAITH Core -- event bus
    if WRAITH then
        pcall(function() WRAITH.init(_eng) end)
        print("[SystemsCheck] WRAITH init done.")

        -- Wire Skippy slot to bridge URL (bridge.py wraith_event_processor)
        -- File-based: no URL needed -- WRAITHBridge handles the file write
        pcall(function()
            WRAITH.setBrain("companion", "file://wraith_events.json")
        end)
    end

    -- WRAITH Bridge -- event file writer + response reader
    if WRAITHBridge and WRAITH then
        pcall(function()
            WRAITHBridge.init(_eng)
            WRAITHBridge.wire(WRAITH)   -- auto-subscribe bridge to all bus events
        end)
        print("[SystemsCheck] WRAITHBridge wired to event bus.")
    end

    -- Fire a startup event so we can confirm the loop immediately
    if WRAITH then
        pcall(function()
            -- Small delay so bridge.py has time to notice the file
            local e = _eng
            if e and e.SetTimeout then
                e.SetTimeout(3.0, function()
                    WRAITH.emit("skippy_say", {
                        text = "Systems check. I'm online. Night City's not going anywhere."
                    })
                    print("[SystemsCheck] Boot event fired -> wraith_events.json")
                end)
            end
        end)
    end

    print("[SystemsCheck] ========================================")
    print("[SystemsCheck]  V12 SYSTEMS CHECK ACTIVE")
    print("[SystemsCheck]  Watch bridge.py terminal for:")
    print("[SystemsCheck]    [FileWatcher] -- game state feed")
    print("[SystemsCheck]    [WRAITH]      -- event bus")
    print("[SystemsCheck]    [Skippy]      -- AI response")
    print("[SystemsCheck] ========================================")
end

-- ============================================================================
-- UPDATE -- called every frame by DevLoader
-- ============================================================================

function SystemsCheck.update(dt, params)
    params = params or {}

    -- Feed BridgeSender
    if BridgeSender then
        pcall(function() BridgeSender.update(dt, params) end)
    end

    -- Poll WRAITH response file so Skippy's replies come back in
    if WRAITHBridge then
        pcall(function() WRAITHBridge.update(dt) end)
    end
end

-- ============================================================================
-- SHUTDOWN
-- ============================================================================

function SystemsCheck.shutdown()
    if BridgeSender then pcall(function() BridgeSender.shutdown() end) end
    if WRAITHBridge  then pcall(function() WRAITHBridge.shutdown()  end) end
    print("[SystemsCheck] All systems shutdown.")
end

-- ============================================================================
-- LOAD ON REQUIRE
-- ============================================================================

loadModules()

return SystemsCheck
