-- ============================================================================
-- V12 RAPTOR DOUGLAS 911 -- modules/cameraSystem.lua
-- Camera Immersion System
--
-- Systems:
--   Eyelid     : inkText bars close based on drunk level, organic tremor
--   Squigglies : drifting character lines in the visible band
--   DrunkSpin  : precession ghost overlays (feeds from voiceSystem or standalone)
--   Meditation : ambient particle visuals -- 3s/10s/60s progression
--   Milkdrop   : full character art show at 60s sustained meditation
--   Shift API  : intoxicated preset at matching drunk intensity (Phase 2)
--
-- DevLoader test: drop in V12_DevLoader/modules/ as cameraSystem.lua
-- State input via update(dt, params) -- see params table at bottom
--
-- Pure ASCII. Lua 5.1.
-- ============================================================================

local CameraSystem = {}

local _eng   = nil
local _shift = nil
local function getEng()   if not _eng   then _eng   = GetMod("0-Engine") end return _eng   end
local function getShift() if not _shift then _shift = GetMod("Shift")    end return _shift end

local function getContainer()
    local inkSys = Game.GetInkSystem()
    if not inkSys then return nil end
    local hudLayer = inkSys:GetLayer(StringToName("inkHUDLayer"))
    return hudLayer and hudLayer:GetVirtualWindow()
end

local function makeWidget(id, fontSize, anchor, anchorPt, marginFn)
    local container = getContainer()
    if not container then return nil end
    local ex = container:GetWidget(StringToName(id))
    if ex then pcall(function() container:RemoveChild(ex) end) end
    local w = inkText.new()
    w:SetName(StringToName(id))
    w:SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily")
    w:SetFontSize(fontSize)
    w:SetAnchor(anchor)
    w:SetAnchorPoint(anchorPt[1], anchorPt[2])
    w:Reparent(container, -1)
    if marginFn then
        pcall(function()
            local _, h = GetDisplayResolution()
            w:SetMargin(marginFn(h or 1080))
        end)
    end
    w:SetVisible(false)
    return w
end

local function removeWidget(id)
    local container = getContainer()
    if not container then return end
    pcall(function()
        local w = container:GetWidget(StringToName(id))
        if w then container:RemoveChild(w) end
    end)
end

local state = {
    pulse        = 0.0,
    drunkLevel   = 0.0,
    nerveLevel   = 1.0,
    isInVehicle  = false,
    isStationary = false,
    stationaryTimer = 0.0,
    prevSpeed    = 0.0,
    eyelidTop    = nil,
    eyelidBot    = nil,
    eyelidCover  = 0.0,
    eyelidTarget = 0.0,
    squigWidget  = nil,
    squigPhase   = 0.0,
    meditWidget  = nil,
    meditPhase   = 0,
    meditTimer   = 0.0,
    dissolving   = false,
    dissolveTimer= 0.0,
    lastMouseX   = 0.0,
    lastMouseY   = 0.0,
    shakeEnergy  = 0.0,
}

local EYELID_CHARS = string.rep("_", 60)

local function buildEyelids()
    if not state.eyelidTop then
        state.eyelidTop = makeWidget("VS_EyelidTop", 22, inkEAnchor.TopCenter, {0.5, 0.0},
            function(h) return inkMargin.new({left=0, top=0, right=0, bottom=0}) end)
    end
    if not state.eyelidBot then
        state.eyelidBot = makeWidget("VS_EyelidBot", 22, inkEAnchor.BottomCenter, {0.5, 1.0},
            function(h) return inkMargin.new({left=0, top=0, right=0, bottom=0}) end)
    end
end

local function updateEyelids(dt)
    local drunk = state.drunkLevel
    state.eyelidTarget = drunk * 0.45
    local speed = 0.8
    state.eyelidCover = state.eyelidCover + (state.eyelidTarget - state.eyelidCover) * speed * dt
    local cover = state.eyelidCover
    if cover < 0.01 then
        if state.eyelidTop then pcall(function() state.eyelidTop:SetVisible(false) end) end
        if state.eyelidBot then pcall(function() state.eyelidBot:SetVisible(false) end) end
        return
    end
    buildEyelids()
    local tremor = math.sin(state.pulse * 7.3) * 0.012 * drunk
                 + math.sin(state.pulse * 13.1) * 0.006 * drunk
    local actualCover = math.max(0, cover + tremor)
    local _, h = GetDisplayResolution()
    local screenH = h or 1080
    local coverPx = actualCover * screenH
    local r = 0.02 + drunk * 0.08
    local g = 0.01
    local b = 0.01
    local a = 0.92
    if state.eyelidTop then
        pcall(function()
            state.eyelidTop:SetText(EYELID_CHARS)
            state.eyelidTop:SetFontSize(math.floor(coverPx * 1.8))
            state.eyelidTop:SetTintColor(HDRColor.new({Red=r, Green=g, Blue=b, Alpha=a}))
            state.eyelidTop:SetVisible(true)
        end)
    end
    if state.eyelidBot then
        pcall(function()
            state.eyelidBot:SetText(EYELID_CHARS)
            state.eyelidBot:SetFontSize(math.floor(coverPx * 1.8))
            state.eyelidBot:SetTintColor(HDRColor.new({Red=r, Green=g, Blue=b, Alpha=a}))
            state.eyelidBot:SetVisible(true)
        end)
    end
end

local SQUIG_CHARS = {"~","~","-","~","~","_","~","/","\\","~","~","-"}

local function buildSquig()
    local lines = {}
    local count = math.random(2, 4)
    for i = 1, count do
        local len  = math.random(4, 12)
        local line = {}
        for j = 1, len do
            table.insert(line, SQUIG_CHARS[math.random(1, #SQUIG_CHARS)])
        end
        table.insert(lines, table.concat(line))
    end
    return table.concat(lines, "\n")
end

local function updateSquigglies(dt)
    local drunk = state.drunkLevel
    if drunk < 0.45 then
        if state.squigWidget then pcall(function() state.squigWidget:SetVisible(false) end) end
        return
    end
    if not state.squigWidget then
        state.squigWidget = makeWidget("VS_Squig", 18, inkEAnchor.Centered, {0.5, 0.5},
            function(h) return inkMargin.new({left=0, top=0, right=0, bottom=0}) end)
    end
    if not state.squigWidget then return end
    state.squigPhase = state.squigPhase + dt
    local _, h = GetDisplayResolution()
    local screenH = h or 1080
    local visibleBand = (1.0 - state.eyelidCover * 2) * screenH * 0.5
    local xDrift = math.sin(state.squigPhase * 0.7 + 1.3) * screenH * 0.18
    local yDrift = math.sin(state.squigPhase * 0.4 + 0.8) * visibleBand * 0.4
    local buildNew = (math.floor(state.squigPhase * 0.5) ~= math.floor((state.squigPhase - dt) * 0.5))
    local alpha = (drunk - 0.45) / 0.55 * 0.7
    pcall(function()
        if buildNew then state.squigWidget:SetText(buildSquig()) end
        state.squigWidget:SetMargin(inkMargin.new({left = xDrift, top = yDrift, right = 0, bottom = 0}))
        local colorShift = math.sin(state.squigPhase * 0.3) * 0.5 + 0.5
        state.squigWidget:SetTintColor(HDRColor.new({
            Red   = 0.6 + colorShift * 0.4,
            Green = 0.2 + colorShift * 0.1,
            Blue  = 0.8 - colorShift * 0.5,
            Alpha = alpha,
        }))
        state.squigWidget:SetVisible(true)
    end)
end

local PARTICLE_CHARS = {".", ":", "+", "o", "*", "x", ".", ".", ".", ":"}
local PATTERN_CHARS  = {"-", "/", "\\", "|", "+", "~", ".", ":", "o", "*"}
local MILKDROP_CHARS = {"#", "@", "%", "&", "8", "0", "O", "Q", "M", "W"}

local function buildParticleField(pulse, density)
    local lines = {}
    for row = 1, 20 do
        local cols = {}
        for col = 1, 42 do
            local wave = math.sin(pulse * 0.8 + row * 0.4 + col * 0.3) * 0.5 + 0.5
            if math.random() < density * wave then
                table.insert(cols, PARTICLE_CHARS[math.random(1, #PARTICLE_CHARS)])
            else table.insert(cols, " ") end
        end
        table.insert(lines, table.concat(cols))
    end
    return table.concat(lines, "\n")
end

local function buildPatternField(pulse)
    local lines = {}
    for row = 1, 22 do
        local cols = {}
        for col = 1, 44 do
            local wave1 = math.sin(pulse * 0.6 + col * 0.25) * 0.5 + 0.5
            local wave2 = math.cos(pulse * 0.4 + row * 0.3) * 0.5 + 0.5
            local combined = (wave1 + wave2) / 2
            if combined > 0.65 then table.insert(cols, PATTERN_CHARS[math.random(1, #PATTERN_CHARS)])
            elseif combined > 0.45 then table.insert(cols, ".")
            else table.insert(cols, " ") end
        end
        table.insert(lines, table.concat(cols))
    end
    return table.concat(lines, "\n")
end

local function buildMilkdropField(pulse)
    local lines = {}
    local cx, cy = 22, 11
    for row = 1, 22 do
        local cols = {}
        for col = 1, 44 do
            local dx = (col - cx) / 22.0
            local dy = (row - cy) / 11.0
            local dist = math.sqrt(dx*dx + dy*dy)
            local ring   = math.sin(dist * 8.0 - pulse * 2.5) * 0.5 + 0.5
            local angle  = math.atan2(dy, dx)
            local spiral = math.sin(angle * 3.0 + dist * 5.0 - pulse * 1.8) * 0.5 + 0.5
            local combined = (ring * 0.6 + spiral * 0.4)
            local idx = math.max(1, math.min(#MILKDROP_CHARS, math.floor(combined * #MILKDROP_CHARS) + 1))
            if combined > 0.55 then table.insert(cols, MILKDROP_CHARS[idx])
            elseif combined > 0.35 then table.insert(cols, PATTERN_CHARS[math.random(1, #PATTERN_CHARS)])
            else table.insert(cols, " ") end
        end
        table.insert(lines, table.concat(cols))
    end
    return table.concat(lines, "\n")
end

local meditColors = {
    {r=0.2, g=0.8, b=0.6},
    {r=0.4, g=0.6, b=1.0},
    {r=0.9, g=0.2, b=0.8},
}

local function updateMeditation(dt, speed, isNearMedSpot)
    local isStationary = (math.abs(speed) < 2.0)
    if not isStationary or state.isInVehicle then
        if state.meditPhase > 0 and not state.dissolving then
            state.dissolving    = true
            state.dissolveTimer = 0.0
        end
        state.stationaryTimer = 0.0
        state.meditPhase      = 0
    else
        state.stationaryTimer = state.stationaryTimer + dt
        if     state.stationaryTimer >= 60.0 then state.meditPhase = 3
        elseif state.stationaryTimer >= 10.0 then state.meditPhase = 2
        elseif state.stationaryTimer >=  3.0 then state.meditPhase = 1
        else   state.meditPhase = 0 end
    end
    if state.dissolving then
        state.dissolveTimer = state.dissolveTimer + dt
        if state.dissolveTimer >= 2.5 then
            state.dissolving = false
            removeWidget("VS_Medit")
            state.meditWidget = nil
        end
    end
    if state.meditPhase == 0 then
        if state.meditWidget and not state.dissolving then
            pcall(function() state.meditWidget:SetVisible(false) end)
        end
        return
    end
    if not state.meditWidget then
        state.meditWidget = makeWidget("VS_Medit", 12, inkEAnchor.Centered, {0.5, 0.5},
            function(h) return inkMargin.new({left=0, top=0, right=0, bottom=0}) end)
    end
    if not state.meditWidget then return end
    local phase    = state.meditPhase
    local col      = meditColors[phase]
    local field
    local baseAlpha = state.dissolving and math.max(0.0, 1.0 - state.dissolveTimer / 2.5) or 1.0
    local phaseAge  = state.stationaryTimer - ({3.0, 10.0, 60.0})[phase]
    local fadeIn    = math.min(1.0, phaseAge / 3.0)
    local alpha     = baseAlpha * fadeIn
    local pulse     = state.pulse
    local colorPulse = math.sin(pulse * 0.5) * 0.3 + 0.7
    if phase == 1 then
        field = buildParticleField(pulse, 0.06)
        alpha = alpha * 0.55
    elseif phase == 2 then
        field = buildPatternField(pulse)
        alpha = alpha * 0.65
        local t = math.sin(pulse * 0.25) * 0.5 + 0.5
        col = { r = 0.2 + t * 0.6, g = 0.7 - t * 0.4, b = 1.0 - t * 0.3 }
    elseif phase == 3 then
        field = buildMilkdropField(pulse)
        alpha = alpha * 0.72
        local t = (pulse * 0.2) % 1.0
        col = {
            r = math.sin(t * math.pi * 2.0) * 0.5 + 0.5,
            g = math.sin(t * math.pi * 2.0 + 2.09) * 0.5 + 0.5,
            b = math.sin(t * math.pi * 2.0 + 4.19) * 0.5 + 0.5,
        }
    end
    pcall(function()
        state.meditWidget:SetText(field)
        state.meditWidget:SetTintColor(HDRColor.new({
            Red   = col.r * colorPulse,
            Green = col.g * colorPulse,
            Blue  = col.b * colorPulse,
            Alpha = alpha,
        }))
        state.meditWidget:SetVisible(alpha > 0.01)
    end)
end

local shiftDrunkActive = false

local function updateShiftCamera(drunkLevel)
    local shift = getShift()
    if not shift or not shift.api then return end
    if drunkLevel > 0.1 and not shiftDrunkActive then
        pcall(function() shift.api.SetCameraShakeEnabled(true) end)
        shiftDrunkActive = true
    elseif drunkLevel <= 0.05 and shiftDrunkActive then
        pcall(function() shift.api.SetCameraShakeEnabled(true) end)
        shiftDrunkActive = false
    end
end

function CameraSystem.update(dt, params)
    params = params or {}
    state.pulse       = state.pulse + dt
    state.drunkLevel  = params.drunkLevel  or 0.0
    state.nerveLevel  = params.nerveLevel  or 1.0
    state.isInVehicle = params.isInVehicle or false
    local speed = params.speed or 0.0
    updateEyelids(dt)
    updateSquigglies(dt)
    updateMeditation(dt, speed, params.isNearMedSpot or false)
    updateShiftCamera(state.drunkLevel)
end

function CameraSystem.init()
    state.pulse           = 0.0
    state.drunkLevel      = 0.0
    state.nerveLevel      = 1.0
    state.eyelidCover     = 0.0
    state.stationaryTimer = 0.0
    state.meditPhase      = 0
    state.dissolving      = false
    shiftDrunkActive      = false
    print("[V12 CameraSystem] Initialised.")
end

function CameraSystem.shutdown()
    removeWidget("VS_EyelidTop")
    removeWidget("VS_EyelidBot")
    removeWidget("VS_Squig")
    removeWidget("VS_Medit")
    state.eyelidTop   = nil
    state.eyelidBot   = nil
    state.squigWidget = nil
    state.meditWidget = nil
    print("[V12 CameraSystem] Shutdown.")
end

function CameraSystem.testDrunk(level)
    state.drunkLevel = level or 0.8
    print("[V12 CameraSystem] Drunk level: " .. tostring(state.drunkLevel))
end

function CameraSystem.testMedit(phase)
    state.meditPhase      = phase or 2
    state.stationaryTimer = ({0, 5, 15, 65})[state.meditPhase + 1] or 5
    print("[V12 CameraSystem] Meditation phase: " .. tostring(state.meditPhase))
end

function CameraSystem.testSober()
    state.drunkLevel    = 0.0
    state.meditPhase    = 0
    state.dissolving    = true
    state.dissolveTimer = 0.0
    print("[V12 CameraSystem] Sobering up...")
end

return CameraSystem
