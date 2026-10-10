-- ============================================================================
-- MANUAL TRANSMISSION V12 RAPTOR DOUGLAS 911 -- modules/introSequence.lua
-- SECRET INITIATION + MENTOR SEQUENCE
-- Face 1 -- INITIATION: triggers after 10 Red fails, first time only.
--           Full screen freeze, glitch, face materializes, congratulates.
-- Face 2 -- MENTOR: triggers every 5 Red fails after initiation.
--           Soft corner popup, practical tips, warm and brief.
-- Features: animated mouth phoneme cycle, eye blink, floating bob,
--           body texture ripple, synthetic gradient lighting.
-- Pure ASCII -- Lua 5.1 compatible.
-- ============================================================================

local Intro = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local cfg = {
    initiationFailThreshold = 10,   -- fails before initiation fires
    mentorFailInterval      = 5,    -- fails between mentor appearances
    glitchDuration          = 0.8,
    staticDuration          = 0.4,
    materializeDuration     = 1.8,
    fadeoutDuration         = 0.8,
    mentorDuration          = 8.0,  -- how long mentor stays on screen
}

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
    active       = false,
    mode         = "none",      -- "initiation" or "mentor"
    phase        = 0,
    phaseTimer   = 0.0,
    pulse        = 0.0,
    bobOffset    = 0.0,
    blinkTimer   = 0.0,
    blinkOpen    = true,
    mouthIdx     = 1,
    mouthTimer   = 0.0,
    msgIndex     = 0,
    msgTimer     = 0.0,
    failCount    = 0,
    mentorCount  = 0,
    seen         = false,
    overlayWidget= nil,
    faceWidget   = nil,
    bodyWidget   = nil,
    msgWidget    = nil,
}

-- ============================================================================
-- PERSISTENT FLAG
-- ============================================================================
local function getEng()
    return GetMod("0-Engine")
end

local function loadPersist()
    local eng = getEng()
    if not eng then return end
    pcall(function()
        local seen = eng.GetData("V12.introSeen")
        if seen == true then state.seen = true end
        local fc = eng.GetData("V12.redFailCount")
        if type(fc) == "number" then state.failCount = fc end
        local mc = eng.GetData("V12.mentorCount")
        if type(mc) == "number" then state.mentorCount = mc end
    end)
end

local function savePersist()
    local eng = getEng()
    if not eng then return end
    pcall(function()
        eng.SetData("V12.introSeen",    state.seen)
        eng.SetData("V12.redFailCount", state.failCount)
        eng.SetData("V12.mentorCount",  state.mentorCount)
    end)
end

-- ============================================================================
-- CHARACTER POOLS
-- ============================================================================
local glitchChars = { "#","@","%","&","?","!","|","/","\\","<",">","X","V","Z","0","1","8","[","]","{","}","~" }
local shadeChars  = { " ","."," ",":","-","=","+","*","#","@","%" }

local function randGlitch() return glitchChars[math.random(1, #glitchChars)] end

local function shadeAt(density)
    local idx = math.max(1, math.min(#shadeChars, math.floor(density * #shadeChars) + 1))
    return shadeChars[idx]
end

-- ============================================================================
-- FACE ANATOMY
-- Row indices (1-based): 1=top, 3=brow, 4-5=eyes, 6=nose, 7=cheek, 8=mouth, 9=jaw, 11=chin
-- ============================================================================
local faceTemplate = {
    "     . . . . . . . . .     ",   -- 1  top
    "   . . . . . . . . . . .   ",   -- 2  forehead
    "   . # # . . . . # # . .   ",   -- 3  brow
    "   . # # . . . . # # . .   ",   -- 4  upper eye
    "   . # # . . . . # # . .   ",   -- 5  lower eye  (blink replaces with dots)
    "   . . . . # . . . . . .   ",   -- 6  nose
    "   . . . . . . . . . . .   ",   -- 7  cheek
    "   . # # # # # # # # . .   ",   -- 8  MOUTH ROW
    "   . . . . . . . . . . .   ",   -- 9  jaw
    "   . . # # # # # # . . .   ",   -- 10 chin
    "     . . . . . . . . .     ",   -- 11 bottom
}

local eyeOpen   = "   . # # . . . . # # . .   "
local eyeClosed = "   . . . . . . . . . . .   "

-- Phoneme mouth shapes -- laughter, speech, rest
local mouthShapes = {
    "   . # # # # # # # # . .   ",  -- wide open laugh
    "   . . # # # # # # . . .   ",  -- mid open
    "   . # . . . . . . # . .   ",  -- corners grin
    "   . . . # # # # . . . .   ",  -- small open
    "   . # # # # # # # # . .   ",  -- wide open again
    "   . # . # . # . # . # .   ",  -- glitch teeth
    "   . . . . . . . . . . .   ",  -- closed rest
    "   . # # . . . . # # . .   ",  -- side grin
}

local function getFaceLines(noiseLevel)
    local lines = {}
    for i, row in ipairs(faceTemplate) do
        local line = row
        -- Eye blink
        if (i == 4 or i == 5) and not state.blinkOpen then
            line = eyeClosed
        end
        -- Mouth phoneme
        if i == 8 then
            line = mouthShapes[((state.mouthIdx - 1) % #mouthShapes) + 1]
        end
        -- Noise corruption
        if noiseLevel > 0 then
            local chars = {}
            for c in line:gmatch(".") do
                if math.random() < noiseLevel then
                    table.insert(chars, randGlitch())
                else
                    table.insert(chars, c)
                end
            end
            line = table.concat(chars)
        end
        table.insert(lines, line)
    end
    return lines
end

-- Build face text with gradient lighting
-- Top rows = lighter (monitor glow from above), bottom = darker
local function buildFaceText(noiseLevel)
    local lines = getFaceLines(noiseLevel)
    return table.concat(lines, "\n")
end

-- ============================================================================
-- BODY TEXTURE -- rippling shade field beneath the face
-- ============================================================================
local function buildBodyTexture(pulse)
    local rows = {}
    for row = 1, 4 do
        local cols = {}
        for col = 1, 28 do
            -- 2D sine creates ripple pattern
            local wave = math.sin(pulse * 2.5 + row * 0.6 + col * 0.25) * 0.5
                       + math.sin(pulse * 1.8 + row * 0.3 - col * 0.18) * 0.3
            local density = math.max(0.0, math.min(1.0, wave * 0.5 + 0.35))
            -- Edges darker -- vignette effect
            local edgeDist = math.min(col, 29 - col) / 14.0
            density = density * edgeDist
            table.insert(cols, shadeAt(density))
        end
        table.insert(rows, table.concat(cols))
    end
    return table.concat(rows, "\n")
end

-- ============================================================================
-- GLITCH OVERLAY
-- ============================================================================
local function buildGlitchField(density, pulse)
    local lines = {}
    for row = 1, 22 do
        local cols = {}
        for col = 1, 42 do
            local wave = math.sin(pulse * 3.0 + row * 0.4 + col * 0.15) * 0.5 + 0.5
            local localDensity = density * wave
            if math.random() < density * 0.08 then
                table.insert(cols, randGlitch())
            else
                table.insert(cols, shadeAt(localDensity))
            end
        end
        table.insert(lines, table.concat(cols))
    end
    return table.concat(lines, "\n")
end

-- ============================================================================
-- MESSAGES
-- ============================================================================
local initiationMessages = {
    { text = "HAHAHA... HA... HA.",             delay = 1.2, r=0.9, g=0.9, b=0.9 },
    { text = "WE BOTH KNOW WHY YOU ARE HERE.",  delay = 1.4, r=0.2, g=1.0, b=0.3 },
    { text = "YOU CHOSE THE HARD WAY.",         delay = 1.2, r=0.2, g=1.0, b=0.3 },
    { text = "MOST DON'T.",                     delay = 1.0, r=0.2, g=1.0, b=0.3 },
    { text = "THE MACHINE RESPECTS THAT.",      delay = 1.3, r=0.2, g=1.0, b=0.3 },
    { text = "GEAR LOCK? REVERSE. THEN DRIVE.", delay = 1.4, r=1.0, g=0.8, b=0.1 },
    { text = "OUR ENGINEERS ARE ON IT.",        delay = 1.0, r=0.5, g=0.5, b=0.5 },
    { text = "ENJOY THE RIDE.",                 delay = 1.0, r=0.2, g=1.0, b=0.3 },
    { text = "ENJOY THE HUMANITY.",             delay = 1.0, r=0.2, g=1.0, b=0.3 },
    { text = "ENJOY YOUR TRANQUILITY.",         delay = 1.4, r=0.2, g=1.0, b=0.3 },
    { text = "-- V12 RD911",                    delay = 2.0, r=0.1, g=0.6, b=1.0 },
}

-- Mentor message pools -- picks one set randomly each appearance
local mentorSets = {
    {
        { text = "STILL LEARNING? GOOD. SO ARE WE.", delay = 1.4, r=0.2, g=1.0, b=0.3 },
        { text = "GEAR STUCK? HIT REVERSE.",         delay = 1.2, r=1.0, g=0.8, b=0.1 },
        { text = "THEN DROP INTO FIRST.",            delay = 1.0, r=1.0, g=0.8, b=0.1 },
        { text = "YOU WILL GET THERE.",              delay = 1.8, r=0.2, g=1.0, b=0.3 },
        { text = "-- V12 RD911",                     delay = 1.0, r=0.1, g=0.6, b=1.0 },
    },
    {
        { text = "THE H-GATE WILL CLICK.",           delay = 1.4, r=0.2, g=1.0, b=0.3 },
        { text = "GIVE IT TIME.",                    delay = 1.0, r=0.2, g=1.0, b=0.3 },
        { text = "NUMPAD. CLUTCH. SHIFT.",           delay = 1.3, r=1.0, g=0.8, b=0.1 },
        { text = "THAT IS ALL IT IS.",               delay = 1.8, r=0.2, g=1.0, b=0.3 },
        { text = "-- V12 RD911",                     delay = 1.0, r=0.1, g=0.6, b=1.0 },
    },
    {
        { text = "NO SHAME IN BLUE.",                delay = 1.4, r=0.3, g=0.5, b=1.0 },
        { text = "BLUE IS FAST. BLUE IS FREE.",      delay = 1.2, r=0.3, g=0.5, b=1.0 },
        { text = "F KEY CYCLES YOUR MODE.",          delay = 1.3, r=1.0, g=0.8, b=0.1 },
        { text = "RED WILL BE HERE WHEN YOU RETURN.",delay = 1.8, r=0.2, g=1.0, b=0.3 },
        { text = "-- V12 RD911",                     delay = 1.0, r=0.1, g=0.6, b=1.0 },
    },
    {
        { text = "CYCLE GEARS WITH NUMPAD.",         delay = 1.4, r=1.0, g=0.8, b=0.1 },
        { text = "NEUTRAL IS NUMPAD ZERO.",          delay = 1.2, r=1.0, g=0.8, b=0.1 },
        { text = "F KEY -- NOT NUMPAD F.",           delay = 1.3, r=1.0, g=0.8, b=0.1 },
        { text = "MODE SWITCH. ALWAYS AVAILABLE.",   delay = 1.8, r=0.2, g=1.0, b=0.3 },
        { text = "-- V12 RD911",                     delay = 1.0, r=0.1, g=0.6, b=1.0 },
    },
}

-- ============================================================================
-- WIDGET BUILDERS
-- ============================================================================
local function getContainer()
    local inkSys = Game.GetInkSystem()
    if not inkSys then return nil end
    local hudLayer = inkSys:GetLayer(StringToName("inkHUDLayer"))
    return hudLayer and hudLayer:GetVirtualWindow()
end

local function buildWidget(id, fontSize, anchor, anchorPt, marginFn)
    local container = getContainer()
    if not container then return nil end
    local existing = container:GetWidget(StringToName(id))
    if existing then container:RemoveChild(existing) end
    local w = inkText.new()
    w:SetName(StringToName(id))
    w:SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily")
    w:SetFontSize(fontSize)
    w:SetAnchor(anchor)
    w:SetAnchorPoint(anchorPt[1], anchorPt[2])
    w:Reparent(container, -1)
    if marginFn then
        pcall(function()
            local sw, sh = GetDisplayResolution()
            w:SetMargin(marginFn(sw or 1920, sh or 1080))
        end)
    end
    w:SetVisible(false)
    return w
end

local function buildWidgets(isMentor)
    if isMentor then
        -- Mentor: compact corner popup, bottom left
        state.faceWidget = buildWidget("V12MentorFace", 18,
            inkEAnchor.BottomLeft, {0.0, 1.0},
            function(w, h) return inkMargin.new({ left = h*0.02, top = 0, right = 0, bottom = h*0.08 }) end)
        state.bodyWidget = buildWidget("V12MentorBody", 12,
            inkEAnchor.BottomLeft, {0.0, 1.0},
            function(w, h) return inkMargin.new({ left = h*0.02, top = 0, right = 0, bottom = h*0.015 }) end)
        state.msgWidget = buildWidget("V12MentorMsg", 16,
            inkEAnchor.BottomLeft, {0.0, 1.0},
            function(w, h) return inkMargin.new({ left = h*0.02, top = 0, right = 0, bottom = h*0.04 }) end)
        state.overlayWidget = nil
    else
        -- Initiation: full screen
        state.overlayWidget = buildWidget("V12IntroOverlay", 13,
            inkEAnchor.TopLeft, {0.0, 0.0},
            function(w, h) return inkMargin.new({ left = 0, top = 0, right = 0, bottom = 0 }) end)
        state.faceWidget = buildWidget("V12IntroFace", 24,
            inkEAnchor.Centered, {0.5, 0.5},
            function(w, h) return inkMargin.new({ left = 0, top = -h*0.08, right = 0, bottom = 0 }) end)
        state.bodyWidget = buildWidget("V12IntroBody", 13,
            inkEAnchor.Centered, {0.5, 0.0},
            function(w, h) return inkMargin.new({ left = 0, top = h*0.22, right = 0, bottom = 0 }) end)
        state.msgWidget = buildWidget("V12IntroMsg", 20,
            inkEAnchor.Centered, {0.5, 0.0},
            function(w, h) return inkMargin.new({ left = 0, top = h*0.62, right = 0, bottom = 0 }) end)
    end
end

local function cleanupWidgets()
    local container = getContainer()
    if not container then return end
    local ids = { "V12IntroOverlay","V12IntroFace","V12IntroBody","V12IntroMsg",
                  "V12MentorFace","V12MentorBody","V12MentorMsg" }
    for _, id in ipairs(ids) do
        pcall(function()
            local w = container:GetWidget(StringToName(id))
            if w then container:RemoveChild(w) end
        end)
    end
    state.overlayWidget = nil
    state.faceWidget    = nil
    state.bodyWidget    = nil
    state.msgWidget     = nil
end

-- ============================================================================
-- AUDIO HELPER
-- Plays AudioWare registered sounds. Falls back to vanilla game sounds.
-- All sounds in the failed_shift/reward pools are already registered.
-- ============================================================================
local laughPool   = { "mt_v10_fail_13", "mt_v10_fail_14", "mt_v10_fail_15" }
local staticPool  = { "mt_v10_fail_01", "mt_v10_fail_02", "mt_v10_fail_03" }
local rewardPool  = { "mt_v10_level10_01", "mt_v10_level10_02", "mt_v10_level10_03" }
local smallPool   = { "mt_v10_small_01", "mt_v10_small_02", "mt_v10_small_03" }

local function playSound(soundName, vol)
    local ok, audioSystem = pcall(function() return Game.GetAudioSystem() end)
    if ok and audioSystem then
        pcall(function() audioSystem:Play(CName.new(soundName), vol or 0.8) end)
    else
        -- Vanilla fallback
        local player = Game.GetPlayer()
        if player then
            pcall(function() player:PlaySound(StringToName("ui_menu_map_pin_added"), nil) end)
        end
    end
end

local function playRandom(pool, vol)
    if not pool or #pool == 0 then return end
    playSound(pool[math.random(1, #pool)], vol)
end

-- ============================================================================
-- GRADIENT COLOR FOR FACE ROW
-- row 1-11, returns r,g,b multipliers (top brighter, bottom darker)
-- ============================================================================
local function rowGradient(rowIdx, totalRows, baseR, baseG, baseB, noiseLevel)
    -- Light source from top-center: brighter at top, darker at bottom
    local topFactor  = 1.0 - (rowIdx - 1) / totalRows * 0.55
    -- Scanline shimmer
    local scan = 0.85 + math.sin(state.pulse * 7.0 + rowIdx * 0.8) * 0.12
    local r = baseR * topFactor * scan + noiseLevel * 0.3
    local g = baseG * topFactor * scan + noiseLevel * 0.1
    local b = baseB * topFactor * scan + noiseLevel * 0.2
    return math.min(1.0, r), math.min(1.0, g), math.min(1.0, b)
end

-- Since inkText is a single widget we fake gradient by using the
-- average brightness across the face, and let the scanline pulse
-- create the illusion of depth. Single color per frame, cycling.
local function faceColor(noiseLevel, rowHint)
    rowHint = rowHint or 5
    local baseR, baseG, baseB = 0.05, 0.92, 0.12
    return rowGradient(rowHint, 11, baseR, baseG, baseB, noiseLevel)
end

-- ============================================================================
-- PHASE LOGIC
-- ============================================================================
local function getCurrentMessages()
    if state.mode == "initiation" then
        return initiationMessages
    else
        local idx = ((state.mentorCount - 1) % #mentorSets) + 1
        return mentorSets[idx]
    end
end

local function startPhase(phase)
    state.phase      = phase
    state.phaseTimer = 0.0

    if phase == 1 then
        if state.mode == "initiation" then
            -- Freeze time
            -- time freeze removed -- SetTimeDilation API differs per version
            if state.overlayWidget then state.overlayWidget:SetVisible(true) end
        end

    elseif phase == 3 then
        if state.faceWidget then state.faceWidget:SetVisible(true) end
        if state.bodyWidget then state.bodyWidget:SetVisible(true) end
        -- Static hit as face begins to materialize
        if state.mode == "initiation" then
            playRandom(staticPool, 0.55)
        end

    elseif phase == 4 then
        state.msgIndex = 0
        state.msgTimer = 0.0
        if state.msgWidget then state.msgWidget:SetVisible(true) end
        -- Restore time for initiation
        if state.mode == "initiation" then
            -- time restore removed -- SetTimeDilation API differs per version
        end

    elseif phase == 5 then
        -- Fade out
    end
end

-- ============================================================================
-- UPDATE
-- ============================================================================
function Intro.update(dt)
    if not state.active then return end

    state.pulse      = state.pulse + dt
    state.phaseTimer = state.phaseTimer + dt

    -- Eye blink logic
    state.blinkTimer = state.blinkTimer + dt
    if state.blinkOpen and state.blinkTimer > 3.2 then
        state.blinkOpen  = false
        state.blinkTimer = 0.0
    elseif not state.blinkOpen and state.blinkTimer > 0.12 then
        state.blinkOpen  = true
        state.blinkTimer = 0.0
    end

    -- Mouth phoneme cycle
    state.mouthTimer = state.mouthTimer + dt
    if state.mouthTimer >= 0.22 then
        state.mouthTimer = 0.0
        state.mouthIdx   = (state.mouthIdx % #mouthShapes) + 1
    end

    -- Floating bob -- sine offset applied to margin (cosmetic)
    state.bobOffset = math.sin(state.pulse * 1.4) * 6.0

    -- ---- PHASE 1: GLITCH ----
    local glitchDur = (state.mode == "initiation") and cfg.glitchDuration or 0.4
    if state.phase == 1 then
        local progress = state.phaseTimer / glitchDur
        local density  = math.min(1.0, progress * 2.0)

        if state.overlayWidget then
            local field = buildGlitchField(density, state.pulse)
            local flash = math.floor(state.pulse * 12) % 2
            pcall(function()
                state.overlayWidget:SetText(field)
                state.overlayWidget:SetTintColor(HDRColor.new({
                    Red   = flash == 0 and 0.08 or 0.3,
                    Green = flash == 0 and 0.9  or 0.6,
                    Blue  = flash == 0 and 0.15 or 0.05,
                    Alpha = math.min(0.88, density)
                }))
            end)
        end

        if state.phaseTimer >= glitchDur then
            startPhase((state.mode == "initiation") and 2 or 3)
        end

    -- ---- PHASE 2: STATIC (initiation only) ----
    elseif state.phase == 2 then
        if state.overlayWidget then
            local flash = math.floor(state.pulse * 20) % 2
            local field = buildGlitchField(1.0, state.pulse)
            pcall(function()
                state.overlayWidget:SetText(field)
                state.overlayWidget:SetTintColor(HDRColor.new({
                    Red   = flash == 0 and 1.0 or 0.04,
                    Green = flash == 0 and 1.0 or 0.04,
                    Blue  = flash == 0 and 1.0 or 0.04,
                    Alpha = 0.96
                }))
            end)
        end
        if state.phaseTimer >= cfg.staticDuration then startPhase(3) end

    -- ---- PHASE 3: MATERIALIZE ----
    elseif state.phase == 3 then
        local matDur   = (state.mode == "initiation") and cfg.materializeDuration or 1.0
        local progress = state.phaseTimer / matDur
        local noise    = math.max(0.0, 1.0 - progress * 1.5)
        local faceAlpha= math.min(1.0, progress * 1.6)
        local scanA    = 0.75 + math.sin(state.pulse * 7.0) * 0.12
        local fr, fg, fb = faceColor(noise, 5)

        if state.faceWidget then
            pcall(function()
                state.faceWidget:SetText(buildFaceText(noise))
                state.faceWidget:SetTintColor(HDRColor.new({
                    Red = fr, Green = fg, Blue = fb,
                    Alpha = faceAlpha * scanA
                }))
                state.faceWidget:SetVisible(true)
            end)
        end

        if state.bodyWidget then
            local bodyAlpha = math.min(0.6, progress * 0.8)
            pcall(function()
                state.bodyWidget:SetText(buildBodyTexture(state.pulse))
                state.bodyWidget:SetTintColor(HDRColor.new({
                    Red = 0.04, Green = 0.7, Blue = 0.1,
                    Alpha = bodyAlpha
                }))
                state.bodyWidget:SetVisible(true)
            end)
        end

        -- Overlay fades as face appears (initiation only)
        if state.overlayWidget then
            local oa = math.max(0.0, 0.88 - progress * 0.88)
            local field = buildGlitchField(0.25, state.pulse)
            pcall(function()
                state.overlayWidget:SetText(field)
                state.overlayWidget:SetTintColor(HDRColor.new({
                    Red = 0.05, Green = 0.7, Blue = 0.1, Alpha = oa
                }))
            end)
        end

        if state.phaseTimer >= matDur then startPhase(4) end

    -- ---- PHASE 4: MESSAGE SCROLL ----
    elseif state.phase == 4 then
        local msgs   = getCurrentMessages()
        local totalDur = (state.mode == "mentor") and cfg.mentorDuration or 999

        -- Animate face
        local noise = 0.0
        local scanA = 0.75 + math.sin(state.pulse * 6.5) * 0.1
        local fr, fg, fb = faceColor(noise, 5)

        if state.faceWidget then
            pcall(function()
                state.faceWidget:SetText(buildFaceText(0.0))
                state.faceWidget:SetTintColor(HDRColor.new({
                    Red = fr, Green = fg, Blue = fb, Alpha = scanA
                }))
            end)
        end

        -- Body ripple
        if state.bodyWidget then
            pcall(function()
                state.bodyWidget:SetText(buildBodyTexture(state.pulse))
                state.bodyWidget:SetTintColor(HDRColor.new({
                    Red = 0.03, Green = 0.65, Blue = 0.08, Alpha = 0.5
                }))
            end)
        end

        -- Message timer
        state.msgTimer = state.msgTimer + dt
        if state.msgIndex < #msgs then
            local currentMsg = msgs[state.msgIndex + 1]
            if state.msgTimer >= (currentMsg and currentMsg.delay or 1.0) then
                state.msgIndex = state.msgIndex + 1
                state.msgTimer = 0.0
                local msg = msgs[state.msgIndex]
                if msg and state.msgWidget then
                    pcall(function()
                        state.msgWidget:SetText(msg.text)
                        state.msgWidget:SetTintColor(HDRColor.new({
                            Red = msg.r, Green = msg.g, Blue = msg.b, Alpha = 1.0
                        }))
                        state.msgWidget:SetVisible(true)
                    end)
                end
                -- Audio cues on specific messages
                if state.mode == "initiation" then
                    if state.msgIndex == 1 then
                        -- HAHAHA -- play a laugh
                        playRandom(laughPool, 0.85)
                    elseif state.msgIndex == 4 then
                        -- THE MACHINE RESPECTS THAT -- subtle small reward
                        playRandom(smallPool, 0.45)
                    elseif state.msgIndex == #msgs then
                        -- Sign-off -- soft chime
                        playRandom(rewardPool, 0.5)
                    end
                elseif state.mode == "mentor" then
                    if state.msgIndex == 1 then
                        -- Mentor opening -- small acknowledgment
                        playRandom(smallPool, 0.4)
                    end
                end
            end
        else
            if state.msgTimer >= 2.0 then startPhase(5) end
        end

        -- Mentor hard timeout
        if state.mode == "mentor" and state.phaseTimer >= totalDur then
            startPhase(5)
        end

    -- ---- PHASE 5: FADE OUT ----
    elseif state.phase == 5 then
        local progress = state.phaseTimer / cfg.fadeoutDuration
        local alpha    = math.max(0.0, 1.0 - progress)

        if state.faceWidget then
            local fr, fg, fb = faceColor(0.0, 5)
            pcall(function()
                state.faceWidget:SetTintColor(HDRColor.new({
                    Red = fr, Green = fg, Blue = fb, Alpha = alpha * 0.9
                }))
            end)
        end
        if state.bodyWidget then
            pcall(function()
                state.bodyWidget:SetTintColor(HDRColor.new({
                    Red = 0.03, Green = 0.65, Blue = 0.08, Alpha = alpha * 0.5
                }))
            end)
        end
        if state.msgWidget then
            pcall(function()
                state.msgWidget:SetTintColor(HDRColor.new({
                    Red = 0.2, Green = 1.0, Blue = 0.3, Alpha = alpha
                }))
            end)
        end

        if state.phaseTimer >= cfg.fadeoutDuration then
            cleanupWidgets()
            state.active = false
            state.phase  = 0
            if state.mode == "initiation" then
                state.seen = true
                print("[V12 RD911] Initiation complete. Welcome.")
            else
                print("[V12 RD911] Mentor dismissed.")
            end
            -- time restore removed -- SetTimeDilation API differs per version
            savePersist()
        end
    end
end

-- ============================================================================
-- TRIGGER
-- ============================================================================
local function fireSequence(mode)
    if state.active then return end
    state.active     = true
    state.mode       = mode
    state.phase      = 0
    state.pulse      = 0.0
    state.blinkTimer = 0.0
    state.blinkOpen  = true
    state.mouthIdx   = 1
    state.mouthTimer = 0.0
    state.msgIndex   = 0
    state.msgTimer   = 0.0
    buildWidgets(mode == "mentor")
    startPhase(1)
    print("[V12 RD911] Sequence fired: " .. mode)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function Intro.onRedFail()
    if state.active then return end
    state.failCount = state.failCount + 1
    savePersist()

    if not state.seen and state.failCount >= cfg.initiationFailThreshold then
        fireSequence("initiation")
        return
    end

    if state.seen then
        local failsSinceInit = state.failCount - cfg.initiationFailThreshold
        if failsSinceInit > 0 and failsSinceInit % cfg.mentorFailInterval == 0 then
            state.mentorCount = state.mentorCount + 1
            fireSequence("mentor")
        end
    end
end

function Intro.init()
    loadPersist()
    print("[V12 RD911] Intro module ready. Seen: " .. tostring(state.seen)
        .. "  Fails: " .. tostring(state.failCount))
end

function Intro.reset()
    state.seen       = false
    state.failCount  = 0
    state.mentorCount= 0
    savePersist()
    print("[V12 RD911] Sequences reset. Fire when ready.")
end

function Intro.testInitiation()
    fireSequence("initiation")
end

function Intro.testMentor()
    state.mentorCount = state.mentorCount + 1
    fireSequence("mentor")
end

-- ============================================================================
-- STREAK REWARD FACES
-- x10 = teasing, gold tint, winking
-- x20 = shameless, red/gold, full send
-- ============================================================================

local streakState = {
    active      = false,
    mode        = "none",
    phase       = 0,
    phaseTimer  = 0.0,
    pulse       = 0.0,
    blinkTimer  = 0.0,
    blinkOpen   = true,
    winking     = false,   -- x10 keeps one eye closed
    mouthIdx    = 1,
    mouthTimer  = 0.0,
    msgIndex    = 0,
    msgTimer    = 0.0,
    faceWidget  = nil,
    bodyWidget  = nil,
    msgWidget   = nil,
}

-- x10 messages -- teasing, suggestive, shift rhythm innuendo
local tease10Sets = {
    {
        { text = "OH MY...",                          delay = 1.0, r=1.0, g=0.85, b=0.2 },
        { text = "TEN PERFECT SHIFTS.",              delay = 1.1, r=1.0, g=0.85, b=0.2 },
        { text = "YOU KNOW HOW TO USE YOUR HANDS.", delay = 1.4, r=1.0, g=0.6,  b=0.1 },
        { text = "KEEP GOING.",                      delay = 1.8, r=1.0, g=0.85, b=0.2 },
    },
    {
        { text = "SMOOTH.",                          delay = 0.9, r=1.0, g=0.85, b=0.2 },
        { text = "VERY SMOOTH.",                     delay = 1.0, r=1.0, g=0.85, b=0.2 },
        { text = "RHYTHM LIKE THAT?",               delay = 1.2, r=1.0, g=0.6,  b=0.1 },
        { text = "CALL ME.",                         delay = 1.8, r=1.0, g=0.85, b=0.2 },
    },
    {
        { text = "MMMM.",                            delay = 0.8, r=1.0, g=0.85, b=0.2 },
        { text = "YOU FEEL THAT?",                  delay = 1.0, r=1.0, g=0.6,  b=0.1 },
        { text = "THAT IS THE GEARBOX PURRING.",    delay = 1.3, r=1.0, g=0.85, b=0.2 },
        { text = "IT LIKES YOU.",                   delay = 1.8, r=1.0, g=0.85, b=0.2 },
    },
}

-- x20 messages -- full shameless Night City energy
local shameless20Sets = {
    {
        { text = "TWENTY.",                          delay = 0.7, r=1.0, g=0.3,  b=0.1 },
        { text = "TWENTY PERFECT SHIFTS.",          delay = 1.0, r=1.0, g=0.3,  b=0.1 },
        { text = "WHO TAUGHT YOU THAT.",            delay = 1.2, r=1.0, g=0.6,  b=0.05 },
        { text = "NIGHT CITY IS WATCHING.",         delay = 1.1, r=1.0, g=0.3,  b=0.1 },
        { text = "THEY ARE ALL WATCHING.",          delay = 1.2, r=1.0, g=0.3,  b=0.1 },
        { text = "GIVE THEM A SHOW.",               delay = 2.0, r=1.0, g=0.75, b=0.0 },
    },
    {
        { text = "OH WE ARE DOING THIS.",           delay = 0.8, r=1.0, g=0.3,  b=0.1 },
        { text = "TWENTY SHIFTS. CLEAN.",           delay = 1.0, r=1.0, g=0.3,  b=0.1 },
        { text = "YOU ABSOLUTE ANIMAL.",            delay = 1.2, r=1.0, g=0.6,  b=0.05 },
        { text = "THE VEHICLE IS YOURS TONIGHT.",  delay = 1.3, r=1.0, g=0.3,  b=0.1 },
        { text = "TAKE IT SOMEWHERE NICE.",        delay = 2.0, r=1.0, g=0.75, b=0.0 },
    },
    {
        { text = "THERE IT IS.",                    delay = 0.8, r=1.0, g=0.3,  b=0.1 },
        { text = "THAT SHIFT AT SEVENTEEN.",       delay = 1.0, r=1.0, g=0.6,  b=0.05 },
        { text = "I FELT THAT ONE.",               delay = 1.1, r=1.0, g=0.3,  b=0.1 },
        { text = "I THINK THE CAR DID TOO.",       delay = 1.2, r=1.0, g=0.3,  b=0.1 },
        { text = "TWENTY. LEGENDARY.",             delay = 2.0, r=1.0, g=0.75, b=0.0 },
    },
}

-- Wink face -- x10 keeps right eye closed seductively
local function getStreakFaceText(winking, mouthIdx)
    local lines = {}
    for i, row in ipairs(faceTemplate) do
        local line = row
        -- Blink logic
        if i == 4 or i == 5 then
            if winking then
                -- Right eye closed, left eye open
                line = "   . # # . . . . . . . .   "
            elseif not streakState.blinkOpen then
                line = eyeClosed
            end
        end
        if i == 8 then
            line = mouthShapes[((mouthIdx - 1) % #mouthShapes) + 1]
        end
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

local function buildStreakWidgets(mode)
    if mode == "tease10" then
        -- Corner popup, right side, warm gold
        streakState.faceWidget = buildWidget("V12Streak10Face", 16,
            inkEAnchor.TopRight, {1.0, 0.0},
            function(w, h) return inkMargin.new({ left = 0, top = h*0.08, right = h*0.02, bottom = 0 }) end)
        streakState.msgWidget = buildWidget("V12Streak10Msg", 15,
            inkEAnchor.TopRight, {1.0, 0.0},
            function(w, h) return inkMargin.new({ left = 0, top = h*0.28, right = h*0.01, bottom = 0 }) end)
    else
        -- Center, larger, red energy
        streakState.faceWidget = buildWidget("V12Streak20Face", 22,
            inkEAnchor.Centered, {0.5, 0.5},
            function(w, h) return inkMargin.new({ left = 0, top = -h*0.15, right = 0, bottom = 0 }) end)
        streakState.bodyWidget = buildWidget("V12Streak20Body", 11,
            inkEAnchor.Centered, {0.5, 0.0},
            function(w, h) return inkMargin.new({ left = 0, top = h*0.18, right = 0, bottom = 0 }) end)
        streakState.msgWidget = buildWidget("V12Streak20Msg", 19,
            inkEAnchor.Centered, {0.5, 0.0},
            function(w, h) return inkMargin.new({ left = 0, top = h*0.55, right = 0, bottom = 0 }) end)
    end
end

local function cleanupStreakWidgets()
    local container = getContainer()
    if not container then return end
    local ids = { "V12Streak10Face","V12Streak10Msg","V12Streak20Face","V12Streak20Body","V12Streak20Msg" }
    for _, id in ipairs(ids) do
        pcall(function()
            local w = container:GetWidget(StringToName(id))
            if w then container:RemoveChild(w) end
        end)
    end
    streakState.faceWidget = nil
    streakState.bodyWidget = nil
    streakState.msgWidget  = nil
end

-- ============================================================================
-- STREAK FACE UPDATE
-- ============================================================================
function Intro.updateStreak(dt)
    if not streakState.active then return end

    streakState.pulse      = streakState.pulse + dt
    streakState.phaseTimer = streakState.phaseTimer + dt

    -- Blink
    streakState.blinkTimer = streakState.blinkTimer + dt
    if streakState.blinkOpen and streakState.blinkTimer > 2.8 then
        streakState.blinkOpen  = false
        streakState.blinkTimer = 0.0
    elseif not streakState.blinkOpen and streakState.blinkTimer > 0.1 then
        streakState.blinkOpen  = true
        streakState.blinkTimer = 0.0
    end

    -- Mouth -- x20 cycles faster
    streakState.mouthTimer = streakState.mouthTimer + dt
    local mouthSpeed = streakState.mode == "shameless20" and 0.16 or 0.26
    if streakState.mouthTimer >= mouthSpeed then
        streakState.mouthTimer = 0.0
        streakState.mouthIdx   = (streakState.mouthIdx % #mouthShapes) + 1
    end

    local isX20  = streakState.mode == "shameless20"
    local msgs   = isX20
        and shameless20Sets[((math.floor(streakState.pulse) % #shameless20Sets) + 1)]
        or  tease10Sets[((math.floor(streakState.pulse) % #tease10Sets) + 1)]

    -- Phase 1: materialize
    if streakState.phase == 1 then
        local progress = streakState.phaseTimer / 0.6
        local noise    = math.max(0.0, 1.0 - progress * 1.8)
        local alpha    = math.min(1.0, progress * 2.0)
        local scan     = 0.8 + math.sin(streakState.pulse * 7.0) * 0.1

        local baseR = isX20 and 1.0 or 1.0
        local baseG = isX20 and 0.25 or 0.8
        local baseB = isX20 and 0.05 or 0.1

        if streakState.faceWidget then
            pcall(function()
                streakState.faceWidget:SetText(getStreakFaceText(
                    not isX20, streakState.mouthIdx))
                streakState.faceWidget:SetTintColor(HDRColor.new({
                    Red = baseR, Green = baseG, Blue = baseB,
                    Alpha = alpha * scan
                }))
                streakState.faceWidget:SetVisible(true)
            end)
        end

        if streakState.phaseTimer >= 0.6 then
            streakState.phase     = 2
            streakState.phaseTimer= 0.0
            streakState.msgIndex  = 0
            streakState.msgTimer  = 0.0
            if streakState.msgWidget then streakState.msgWidget:SetVisible(true) end
            -- Play appropriate reward sound when face speaks
            if isX20 then
                local pool20 = { "mt_v10_level20_01","mt_v10_level20_02","mt_v10_level20_03" }
                playRandom(pool20, 0.75)
            else
                playRandom(rewardPool, 0.65)
            end
        end

    -- Phase 2: messages
    elseif streakState.phase == 2 then
        local baseR = isX20 and 1.0 or 1.0
        local baseG = isX20 and 0.25 or 0.8
        local baseB = isX20 and 0.05 or 0.1
        local scan  = 0.78 + math.sin(streakState.pulse * 6.0) * 0.1

        if streakState.faceWidget then
            pcall(function()
                streakState.faceWidget:SetText(getStreakFaceText(
                    not isX20, streakState.mouthIdx))
                streakState.faceWidget:SetTintColor(HDRColor.new({
                    Red = baseR, Green = baseG, Blue = baseB, Alpha = scan
                }))
            end)
        end

        if streakState.bodyWidget and isX20 then
            pcall(function()
                streakState.bodyWidget:SetText(buildBodyTexture(streakState.pulse))
                streakState.bodyWidget:SetTintColor(HDRColor.new({
                    Red = 0.8, Green = 0.15, Blue = 0.02, Alpha = 0.45
                }))
                streakState.bodyWidget:SetVisible(true)
            end)
        end

        streakState.msgTimer = streakState.msgTimer + dt
        if streakState.msgIndex < #msgs then
            local cur = msgs[streakState.msgIndex + 1]
            if streakState.msgTimer >= (cur and cur.delay or 1.0) then
                streakState.msgIndex = streakState.msgIndex + 1
                streakState.msgTimer = 0.0
                local msg = msgs[streakState.msgIndex]
                if msg and streakState.msgWidget then
                    pcall(function()
                        streakState.msgWidget:SetText(msg.text)
                        streakState.msgWidget:SetTintColor(HDRColor.new({
                            Red = msg.r, Green = msg.g, Blue = msg.b, Alpha = 1.0
                        }))
                    end)
                end
            end
        else
            if streakState.msgTimer >= 1.8 then
                streakState.phase     = 3
                streakState.phaseTimer= 0.0
            end
        end

    -- Phase 3: fade out
    elseif streakState.phase == 3 then
        local alpha = math.max(0.0, 1.0 - streakState.phaseTimer / 0.6)
        local baseR = isX20 and 1.0 or 1.0
        local baseG = isX20 and 0.25 or 0.8
        local baseB = isX20 and 0.05 or 0.1

        if streakState.faceWidget then
            pcall(function()
                streakState.faceWidget:SetTintColor(HDRColor.new({
                    Red = baseR, Green = baseG, Blue = baseB, Alpha = alpha
                }))
            end)
        end
        if streakState.msgWidget then
            pcall(function()
                streakState.msgWidget:SetTintColor(HDRColor.new({
                    Red = 1.0, Green = 0.8, Blue = 0.2, Alpha = alpha
                }))
            end)
        end

        if streakState.phaseTimer >= 0.6 then
            cleanupStreakWidgets()
            streakState.active = false
            streakState.phase  = 0
        end
    end
end

-- ============================================================================
-- STREAK TRIGGER API
-- ============================================================================
function Intro.onStreak10()
    if streakState.active or state.active then return end
    streakState.active     = true
    streakState.mode       = "tease10"
    streakState.phase      = 1
    streakState.phaseTimer = 0.0
    streakState.pulse      = 0.0
    streakState.blinkTimer = 0.0
    streakState.blinkOpen  = true
    streakState.mouthIdx   = 1
    streakState.mouthTimer = 0.0
    streakState.msgIndex   = 0
    streakState.msgTimer   = 0.0
    buildStreakWidgets("tease10")
    print("[V12 RD911] Streak x10 -- tease face fired.")
end

function Intro.onStreak20()
    if streakState.active or state.active then return end
    streakState.active     = true
    streakState.mode       = "shameless20"
    streakState.phase      = 1
    streakState.phaseTimer = 0.0
    streakState.pulse      = 0.0
    streakState.blinkTimer = 0.0
    streakState.blinkOpen  = true
    streakState.mouthIdx   = 1
    streakState.mouthTimer = 0.0
    streakState.msgIndex   = 0
    streakState.msgTimer   = 0.0
    buildStreakWidgets("shameless20")
    print("[V12 RD911] Streak x20 -- shameless face fired.")
end

return Intro