-- ============================================================================
-- V12 RAPTOR DOUGLAS 911
-- W.R.A.I.T.H. -- wraith_bridge.lua
-- Provider-Agnostic Bridge Protocol
--
-- This module is the translator between Night City and whatever brain
-- is plugged into the WRAITH provider slots.
--
-- HOW IT WORKS:
--   WRAITH events -> wraith_events.json  (Lua writes, bridge reads)
--   game_state    -> game_state.json     (bridgeSender already handles this)
--   bridge speaks -> Piper TTS -> your ears (bridge.py handles this)
--
-- Pure ASCII. Lua 5.1.
-- ============================================================================

local WRAITHBridge = {}

-- CET sandboxes io.open writes -- we POST events via curl instead
local EVENTS_URL  = "http://127.0.0.1:5000/wraith_event"

local _queue         = {}
local _flushInterval = 1.0
local _lastFlush     = 0
local _sessionStart  = os.time and os.time() or 0
local MAX_QUEUE      = 8

local _lastResponseMtime = 0

local function _pollResponse(wraith)
    pcall(function()
        local f = io.open(RESPONSE_FILE, "r")
        if not f then return end
        local content = f:read("*all")
        f:close()
        if not content or content == "" then return end
        local hash = 0
        for i = 1, math.min(#content, 64) do
            hash = (hash * 31 + string.byte(content, i)) % 65536
        end
        if hash == _lastResponseMtime then return end
        _lastResponseMtime = hash
        local speak = content:match('"speak"%s*:%s*"([^"]*)"')
        local emit_raw = content:match('"emit"%s*:%s*%[([^%]]*)%]')
        if speak and speak ~= "" and wraith then
            print("[WRAITH Bridge] Speaking: " .. speak)
            wraith.emit("skippy_say", { text = speak })
        end
        if emit_raw and wraith then
            for ev in emit_raw:gmatch('"([^"]+)"') do
                wraith.emit(ev, { source = "bridge" })
            end
        end
    end)
end

local function _escapeStr(s)
    s = tostring(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"',  '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    return s
end

local function _stateToJson(state)
    if not state then return '{}' end
    return string.format(
        '{"nerve":%.1f,"phase":%d,"speed":%.1f,"health_pct":%.1f,"enemies_near":%d,"in_combat":%s,"district":"%s","mode":"%s","stress":%.1f,"adrenaline":%.1f,"wanted":%d}',
        state.nerve        or 100.0,
        state.phase        or 1,
        state.speed        or 0.0,
        state.health_pct   or 100.0,
        state.enemies_near or 0,
        state.in_combat    and "true" or "false",
        _escapeStr(state.district  or "unknown"),
        _escapeStr(state.mode      or "green"),
        state.stress       or 0.0,
        state.adrenaline   or 0.0,
        state.wanted       or 0
    )
end

local function _dataToJson(data)
    if not data then return '{}' end
    local parts = {}
    for k, v in pairs(data) do
        local val
        if     type(v) == "number"  then val = tostring(v)
        elseif type(v) == "boolean" then val = v and "true" or "false"
        elseif type(v) == "string"  then val = '"' .. _escapeStr(v) .. '"'
        else                             val = '"' .. _escapeStr(tostring(v)) .. '"'
        end
        table.insert(parts, '"' .. _escapeStr(tostring(k)) .. '":' .. val)
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function _queueToJson(queue)
    local entries = {}
    for _, item in ipairs(queue) do
        local entry = string.format(
            '{"event":"%s","timestamp":%d,"game_state":%s,"data":%s}',
            _escapeStr(item.event),
            item.timestamp,
            _stateToJson(item.game_state),
            _dataToJson(item.data)
        )
        table.insert(entries, entry)
    end
    return '[' .. table.concat(entries, ',') .. ']'
end

local _wiredWraith = nil

local function _postEvent(json)
    pcall(function()
        local escaped = json:gsub('"', '\\"')
        local cmd = 'curl -s -X POST ' .. EVENTS_URL
                 .. ' -H "Content-Type: application/json"'
                 .. ' -d "' .. escaped .. '" >NUL 2>&1'
        local h = io.popen(cmd)
        if h then h:close() end
    end)
end

local function _flush()
    if #_queue == 0 then return end
    local json = _queueToJson(_queue)
    _postEvent(json)
    _queue = {}
end

function WRAITHBridge.push(event, data, game_state)
    if not event then return end
    local ts = 0
    pcall(function() ts = math.floor(os.time and os.time() or 0) end)
    table.insert(_queue, {
        event      = event,
        timestamp  = ts,
        game_state = game_state,
        data       = data or {},
    })
    if #_queue >= MAX_QUEUE then _flush() end
end

function WRAITHBridge.speak(text, game_state)
    WRAITHBridge.push("direct_speak", { text = text }, game_state)
    _flush()
end

function WRAITHBridge.update(dt)
    _lastFlush = (_lastFlush or 0) + dt
    if _lastFlush >= _flushInterval then
        _lastFlush = 0
        _flush()
    end
end

function WRAITHBridge.wire(wraith)
    if not wraith then
        print("[WRAITH Bridge] ERROR: wraith handle required for wire()")
        return
    end
    _wiredWraith = wraith
    local AUTO_PUSH = {
        "kill", "took_damage", "phase_change", "nerve_drop",
        "combat_start", "combat_end", "vehicle_enter",
        "good_shift", "bad_shift", "skippy_say", "custom",
    }
    for _, event in ipairs(AUTO_PUSH) do
        local ev = event
        wraith.on(ev, function(data)
            WRAITHBridge.push(ev, data, wraith.state)
        end)
    end
    print("[WRAITH Bridge] Wired to WRAITH event bus.")
    print("[WRAITH Bridge]   Events POST -> " .. EVENTS_URL)
end

function WRAITHBridge.init(eng)
    _queue      = {}
    _lastFlush  = 0
    _lastResponseMtime = 0
    print("[WRAITH Bridge] Initialised.")
end

function WRAITHBridge.shutdown()
    _flush()
    print("[WRAITH Bridge] Shutdown.")
end

return WRAITHBridge
