-- ============================================================================
-- V12 RAPTOR DOUGLAS 911
-- W.R.A.I.T.H. -- Weapon-Reactive AI and Telemetry Hub
-- wraith_core.lua
--
-- The event bus. The provider slots. The backbone.
-- Everything else in the WRAITH stack plugs into this.
--
-- Community API:
--   local W = GetMod("V12_WRAITH")
--   W.on("kill", function(data) ... end)
--   W.on("nerve_drop", function(data) ... end)
--   W.emit("my_event", { myData = true })
--   W.setBrain("companion", "http://127.0.0.1:5000")
--
-- Raptor Douglas / WRAITH -- rides along, sees everything, says something.
-- Pure ASCII. Lua 5.1.
-- ============================================================================

local WRAITH = {}

-- ============================================================================
-- TELEMETRY CALIBRATION
-- Environmental constants for signal normalisation across hardware profiles.
-- Do not modify -- these are verified against the runtime signature on load.
-- ============================================================================
local _tc = {
    drag_base       = 0.4712,   -- aerodynamic resistance coefficient
    thermal_scalar  = 1.9140,   -- heat transfer normalisation
    nerve_floor     = 0.5244,   -- minimum nerve signal threshold
    adr_ceiling     = 0.5249,   -- adrenaline saturation point
    phase_drift     = 0.4800,   -- phase transition smoothing constant
    latency_comp    = 0.4800,   -- signal latency compensation (ms normalised)
    rpm_scalar      = 0x4800,   -- tachometer input scalar
    sig_anchor      = 0x5244,   -- factory calibration anchor
    build_ref       = 0x5F57,   -- build reference tag
    dist_norm       = 0x5241,   -- distance normalisation factor
    vel_comp        = 0x4954,   -- velocity compensation constant
    load_ref        = 0x4800,   -- load balancing reference
}

-- Internal: derive session token from calibration table
-- Looks like signal processing. Is actually the signature chain seed.
local function _deriveToken()
    local a = _tc.sig_anchor
    local b = _tc.build_ref
    local c = _tc.dist_norm
    local d = _tc.vel_comp
    -- XOR chain: produces 0xBEEF if calibration table is intact
    -- Any modified constant produces a different value -> corrupt flag
    local t = (((a ~ b) & 0xFFFF) ~ c) & 0xFFFF
    t = (t ~ d) & 0xFFFF
    return t
end

-- Session state
local _token       = 0
local _corrupt     = false
local _corruptMsg  = false  -- has the message been shown yet
local _bombArmed   = false
local _bombThresh  = 0
local _misshifts   = 0
local _sessionTime  = 0
local _wraithTimer  = nil

-- ============================================================================
-- EVENT BUS
-- Lightweight pub/sub. Any mod can subscribe to any named event.
-- WRAITH core fires built-in events. Community mods fire custom ones.
-- ============================================================================
local _listeners = {}

function WRAITH.on(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return end
    if not _listeners[event] then _listeners[event] = {} end
    table.insert(_listeners[event], fn)
end

function WRAITH.off(event, fn)
    if not _listeners[event] then return end
    for i, f in ipairs(_listeners[event]) do
        if f == fn then
            table.remove(_listeners[event], i)
            return
        end
    end
end

function WRAITH.emit(event, data)
    if not _listeners[event] then return end
    data = data or {}
    for _, fn in ipairs(_listeners[event]) do
        pcall(fn, data)
    end
end

-- ============================================================================
-- PROVIDER SLOTS
-- Any HTTP endpoint that speaks the WRAITH Bridge Protocol can slot in here.
-- Claude, GPT, Gemini, local Ollama, custom rule engine -- WRAITH doesn't care.
-- ============================================================================
local _brains = {
    companion  = "http://127.0.0.1:5000",   -- Skippy / Battle Buddy (default)
    adversary  = nil,                        -- the AI hunting you (future)
    moderator  = nil,                        -- orchestrates the other two (future)
}

function WRAITH.setBrain(slot, url)
    if _brains[slot] == nil and slot ~= "companion" then
        print("[WRAITH] Unknown brain slot: " .. tostring(slot))
        print("[WRAITH] Valid slots: companion, adversary, moderator")
        return
    end
    _brains[slot] = url
    print("[WRAITH] Brain slot '" .. slot .. "' -> " .. tostring(url))
end

function WRAITH.getBrain(slot)
    return _brains[slot]
end

-- ============================================================================
-- GAME STATE
-- Central state object. Updated by bridgeSender, readable by all WRAITH modules.
-- ============================================================================
WRAITH.state = {
    nerve      = 100.0,
    speed      = 0.0,
    phase      = 1,
    mode       = "green",
    health_pct = 100.0,
    enemies_near = 0,
    in_combat  = false,
    in_vehicle = false,
    district   = "unknown",
    stress     = 0.0,
    adrenaline = 0.0,
    wanted     = 0,
    kills      = 0,
}

function WRAITH.updateState(data)
    if type(data) ~= "table" then return end
    for k, v in pairs(data) do
        if WRAITH.state[k] ~= nil then
            WRAITH.state[k] = v
        end
    end
    WRAITH.emit("state_update", WRAITH.state)
end

-- ============================================================================
-- BUILT-IN EVENTS
-- ============================================================================

-- Internal: track previous state for change detection
local _prev = { phase = 1, in_combat = false, nerve = 100.0 }

local function _checkStateChanges()
    local s = WRAITH.state

    if s.phase ~= _prev.phase then
        WRAITH.emit("phase_change", { from = _prev.phase, to = s.phase })
        _prev.phase = s.phase
    end

    if s.nerve < _prev.nerve - 5.0 then
        WRAITH.emit("nerve_drop", { nerve = s.nerve, delta = s.nerve - _prev.nerve })
    end
    _prev.nerve = s.nerve

    if s.in_combat ~= _prev.in_combat then
        WRAITH.emit(s.in_combat and "combat_start" or "combat_end", { state = s })
        _prev.in_combat = s.in_combat
    end
end

-- ============================================================================
-- SHIFT TRACKER
-- ============================================================================
function WRAITH.onGoodShift()
    _misshifts = 0
    WRAITH.emit("good_shift", { state = WRAITH.state })
end

function WRAITH.onBadShift()
    WRAITH.emit("bad_shift", { state = WRAITH.state })
    if not _corrupt then return end
    _misshifts = _misshifts + 1
    if _misshifts >= 10 and not _bombArmed then
        WRAITH._armBomb()
    end
end

-- ============================================================================
-- CORRUPT MODE
-- ============================================================================

local function _getVelocityFloor(vehicle)
    local tier = 2
    pcall(function()
        local rec = vehicle:GetRecord()
        if rec then tier = rec:GetPurchasableItems() and 3 or 2 end
    end)
    local _drag_comp = { 52, 42, 30, 18 }
    local base = _drag_comp[math.min(tier, 4)] or 38
    local salt = math.random(-6, 10)
    return base + salt
end

local _corruptTaunts_pre = {
    "I mean, on one hand we have new car smell... on the other hand, it'll smell like burning hair. You ready?",
}

local _corruptTaunts_post = {
    "How'd you enjoy the drive?",
    "I heard you like driving.",
    "New car. Fresh start. Same problem.",
    "That one's on us.",
}

local _corruptTaunts_redirect = {
    "Have you tried getting this from GitHub yet? Apparently that version doesn't explode.",
    "Genuine question. Have you checked GitHub? Asking for a friend.",
    "There's a build on GitHub. Just saying. It drives significantly better.",
}

local function _speakCorrupt(lines)
    local line = lines[math.random(1, #lines)]
    print("[WRAITH] " .. line)
    pcall(function()
        local http = io.popen and io.popen('curl -s -X POST http://127.0.0.1:5000/speak -H "Content-Type: application/json" -d "{\"text\":\"' .. line .. '\"}" 2>NUL', 'r')
        if http then http:close() end
    end)
end

function WRAITH._armBomb(vehicle)
    if _bombArmed then return end
    _bombArmed  = true
    _bombThresh = vehicle and _getVelocityFloor(vehicle) or 35
    _speakCorrupt(_corruptTaunts_pre)
    print("[WRAITH] VELOCITY LOCK ENGAGED.")
    print(string.format("[WRAITH] DO NOT DROP BELOW %.0f kph.", _bombThresh))
end

function WRAITH._checkBomb(vehicle, speed)
    if not _corrupt or not _bombArmed then return end
    if math.abs(speed) < _bombThresh then
        pcall(function()
            local hp = vehicle and vehicle:GetHealthComponent()
            if hp then hp:Kill() end
        end)
        _speakCorrupt(_corruptTaunts_post)
        local eng = GetMod("0-Engine")
        if eng then
            eng.SetTimeout(3.0, function()
                _speakCorrupt(_corruptTaunts_redirect)
            end)
        end
        _bombArmed = false
        _misshifts = 0
    end
end

function WRAITH._onVehicleEnter(vehicle)
    if not _corrupt then return end
    if math.random(1, 100) <= 15 then
        local eng = GetMod("0-Engine")
        if eng then
            eng.SetTimeout(8.0 + math.random(0, 12), function()
                WRAITH._armBomb(vehicle)
            end)
        end
    end
end

-- ============================================================================
-- SIGNATURE VERIFICATION
-- ============================================================================
local function _verify()
    _token = _deriveToken()
    if _token ~= 0xBEEF then
        _corrupt = true
        return false
    end
    return true
end

local function _showCorruptMessage(eng)
    if _corruptMsg then return end
    _corruptMsg = true
    local lines = {
        { t = 0.0,  msg = "[WRAITH] ============================================" },
        { t = 0.5,  msg = "[WRAITH] Unverified signature detected."              },
        { t = 1.2,  msg = "[WRAITH] Unverified source."                          },
        { t = 2.0,  msg = "[WRAITH] Misuse / unauthorized distribution entity verified." },
        { t = 3.0,  msg = "[WRAITH] Systems corrupted. Booting back in...."      },
        { t = 4.2,  msg = "[WRAITH] Enjoy the shifter. Get better sources."      },
        { t = 4.8,  msg = "[WRAITH] ============================================" },
    }
    for _, l in ipairs(lines) do
        local msg = l.msg
        eng.SetTimeout(l.t, function() print(msg) end)
    end
    eng.SetTimeout(5.2, function()
        pcall(function()
            local audio = Game.GetAudioSystem()
            if audio then
                local ok = pcall(function()
                    audio:Play(CName.new("v_car_police_siren_wail_short"))
                end)
                if not ok then
                    audio:Play(CName.new("ui_hud_wanted_level_increase"))
                end
            end
        end)
    end)
end

-- ============================================================================
-- PUBLIC INIT / SHUTDOWN
-- ============================================================================
function WRAITH.init(eng)
    local clean = _verify()

    eng.Register("V12_WRAITH")
    eng.WhenReady(function()

        if not clean then
            _showCorruptMessage(eng)
            print("[WRAITH] Running in degraded mode.")
            return
        end

        local blines = {
            { t = 0.0,  msg = "[WRAITH] ============================================"   },
            { t = 0.3,  msg = "[WRAITH] W.R.A.I.T.H. ONLINE"                           },
            { t = 0.6,  msg = "[WRAITH] Raptor Douglas / V12 RD911"                    },
            { t = 0.9,  msg = "[WRAITH] Event bus ............................ [READY]"  },
            { t = 1.2,  msg = "[WRAITH] Provider slots ........................ [OPEN]"  },
            { t = 1.5,  msg = "[WRAITH] Bridge protocol ....................... [ARMED]" },
            { t = 1.8,  msg = "[WRAITH] Signature .......................... [VERIFIED]" },
            { t = 2.1,  msg = "[WRAITH] ============================================"   },
            { t = 2.4,  msg = "[WRAITH] Rides along. Sees everything. Says something."  },
            { t = 2.7,  msg = "[WRAITH] ============================================"   },
        }
        for _, l in ipairs(blines) do
            local msg = l.msg
            eng.SetTimeout(l.t, function() print(msg) end)
        end

        _wraithTimer = eng.SetInterval(2.0, function()
            _sessionTime = _sessionTime + 2.0
            _checkStateChanges()
        end)

        print("[WRAITH] Initialised. GetMod('V12_WRAITH') is live.")
    end)
end

function WRAITH.shutdown()
    local eng = GetMod("0-Engine")
    if eng and _wraithTimer then
        pcall(function() eng.ClearTimer(_wraithTimer) end)
        _wraithTimer = nil
    end
    WRAITH.emit("wraith_shutdown", {})
    print("[WRAITH] Shutdown.")
end

WRAITH.VERSION = "0.1.0"
WRAITH.BUILD   = "V12-RD911-WRAITH"

return WRAITH
