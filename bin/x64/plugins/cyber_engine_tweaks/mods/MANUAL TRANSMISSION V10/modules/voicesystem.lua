-- ============================================================================
-- MANUAL TRANSMISSION V12 RAPTOR DOUGLAS 911 -- modules/voiceSystem.lua
-- Ambient Voice, Reality Disturbance, and Ghost Systems
--
-- DrunkVision   : layered precession ghost overlays (earth axial wobble math)
-- DrunkStagger  : steering sensitivity injection tied to lean physics
-- Whisper       : dark side, pleasant cruise, police hype, highway hypnosis
-- TipSequence   : first x10 streak instructional flipbook
-- Ghost         : the rarest easter egg. 50 clean Red shifts. the machine speaks.
-- Midnight      : if driving Red at in-game midnight. never documented anywhere.
--
-- Pure ASCII. Lua 5.1. No em-dashes. No degree symbols.
-- ============================================================================

local VoiceSystem = {}

-- ============================================================================
-- ENGINE RESOLVER
-- ============================================================================
local _eng = nil
local function getEng()
    if not _eng then _eng = GetMod("0-Engine") end
    return _eng
end

-- ============================================================================
-- WIDGET HELPERS
-- ============================================================================
local function getContainer()
    local inkSys = Game.GetInkSystem()
    if not inkSys then return nil end
    local hudLayer = inkSys:GetLayer(StringToName("inkHUDLayer"))
    return hudLayer and hudLayer:GetVirtualWindow()
end

local function makeWidget(id, fontSize, anchor, anchorPt, marginFn)
    local container = getContainer()
    if not container then return nil end
    local existing = container:GetWidget(StringToName(id))
    if existing then pcall(function() container:RemoveChild(existing) end) end
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

-- ============================================================================
-- DRUNK VISION -- layered precession ghost overlays
-- Three ghost layers at different sine frequencies and phase offsets.
-- Each drifts on an elliptical path. When a ghost ages out it fades
-- and respawns at a new phase so it starts from a different angle.
-- The overlap of three drifting layers at different phases creates
-- the axial wobble pre-spin effect without true rotation.
-- Earth axial precession: 23.5 degrees, never tips over.
-- ============================================================================

local drunkVision = {
    active = false,
    level  = 0.0,
    pulse  = 0.0,
    ghosts = {
        { id="V12DV_A", w=nil, alpha=0.0, freqX=0.23, freqY=0.17,
          phase=0.0,  ampX=185, ampY=72, age=0.0,  maxAge=9.0,  fading=false, target=0.28 },
        { id="V12DV_B", w=nil, alpha=0.0, freqX=0.31, freqY=0.22,
          phase=2.09, ampX=152, ampY=58, age=3.2,  maxAge=12.0, fading=false, target=0.17 },
        { id="V12DV_C", w=nil, alpha=0.0, freqX=0.19, freqY=0.14,
          phase=4.19, ampX=118, ampY=44, age=6.5,  maxAge=15.0, fading=false, target=0.10 },
    },
}

local ghostSparsity = { 0.038, 0.024, 0.014 }
local ghostChars    = { " "," "," ","."," "," ","."," ",":" }

local function buildGhostField(pulse, idx)
    local d = ghostSparsity[idx] or 0.02
    local lines = {}
    for row = 1, 18 do
        local cols = {}
        for col = 1, 36 do
            local wave = math.sin(pulse * 1.1 + row * 0.5 + col * 0.28 + idx * 0.9) * 0.5 + 0.5
            if math.random() < d * wave then
                table.insert(cols, ghostChars[math.random(1, #ghostChars)])
            else
                table.insert(cols, " ")
            end
        end
        table.insert(lines, table.concat(cols))
    end
    return table.concat(lines, "\n")
end

local function updateOneGhost(g, idx, dt, pulse, level)
    g.age = g.age + dt

    -- Fade in toward target alpha
    if not g.fading then
        local want = g.target * level
        if g.alpha < want then
            g.alpha = math.min(want, g.alpha + dt * 0.35)
        elseif g.alpha > want then
            g.alpha = math.max(want, g.alpha - dt * 0.35)
        end
    end

    -- Age out
    if g.age >= g.maxAge then g.fading = true end

    if g.fading then
        g.alpha = math.max(0.0, g.alpha - dt * 0.45)
        if g.alpha <= 0.01 then
            g.age    = 0.0
            g.fading = false
            g.phase  = g.phase + 0.65 + math.random() * 1.3
            if g.w then pcall(function() g.w:SetVisible(false) end) end
            return
        end
    end

    -- Build or rebuild widget if missing
    if not g.w then
        g.w = makeWidget(g.id, 11, inkEAnchor.TopLeft, {0.0, 0.0},
            function(h) return inkMargin.new({left=0, top=0, right=0, bottom=0}) end)
    end
    if not g.w then return end

    -- Elliptical drift -- sine X, cosine Y (smaller vertical excursion)
    local xOff = math.sin(pulse * g.freqX + g.phase) * g.ampX * level
    local yOff = math.cos(pulse * g.freqY + g.phase * 0.7) * g.ampY * level

    local field = buildGhostField(pulse, idx)
    pcall(function()
        g.w:SetText(field)
        g.w:SetMargin(inkMargin.new({ left=xOff, top=yOff, right=0, bottom=0 }))
        g.w:SetTintColor(HDRColor.new({ Red=0.72, Green=0.84, Blue=1.0, Alpha=g.alpha }))
        g.w:SetVisible(g.alpha > 0.01)
    end)
end

local function updateDrunkVision(dt)
    if not drunkVision.active and drunkVision.level <= 0.0 then return end
    drunkVision.pulse = drunkVision.pulse + dt
    for i, g in ipairs(drunkVision.ghosts) do
        updateOneGhost(g, i, dt, drunkVision.pulse, drunkVision.level)
    end
end

function VoiceSystem.setDrunkLevel(level)
    drunkVision.level  = math.max(0.0, math.min(1.0, level))
    drunkVision.active = (drunkVision.level > 0.05)
end

-- ============================================================================
-- DRUNK STAGGER -- steering sensitivity injection
-- Physics: lean chases target, target flips with damping on overshoot.
-- On flip: inject a brief steering modifier (over or under sensitivity).
-- Low drunk = barely felt. BODrunk = genuine mid-corner twitch.
-- Player must counter-steer to compensate. That IS the mechanic.
-- ============================================================================

local stagger = {
    lean       = 0.0,
    velocity   = 0.0,
    target     = 14.0,
    steerMod   = 0.0,
    steerTimer = 0.0,
    level      = 0.0,
    active     = false,
}

function VoiceSystem.setStaggerLevel(level)
    stagger.level  = math.max(0.0, math.min(1.0, level))
    stagger.active = (stagger.level > 0.05)
end

-- Call from init.lua steering input: rawSteering = rawSteering + VoiceSystem.getSteerInjection()
function VoiceSystem.getSteerInjection()
    return stagger.steerMod
end

local function updateStagger(dt)
    if not stagger.active then
        stagger.steerMod = 0.0
        return
    end

    local maxLean = 24.0 * stagger.level

    -- Lean physics
    stagger.velocity = stagger.velocity
                     + (stagger.target - stagger.lean) * 0.30 * stagger.level
    stagger.velocity = stagger.velocity * 0.93  -- damping
    stagger.lean     = stagger.lean + stagger.velocity * dt

    -- Overshoot: flip target with random dampen factor
    if (stagger.lean > maxLean and stagger.target > 0) or
       (stagger.lean < -maxLean and stagger.target < 0) then
        stagger.target = -stagger.target * (0.55 + math.random() * 0.30)
        -- Inject steering disturbance -- direction sometimes matches lean, sometimes fights it
        local dir = (math.random() > 0.45) and 1.0 or -1.0
        stagger.steerMod   = dir * (0.10 + stagger.level * 0.24)
        stagger.steerTimer = 0.22 + math.random() * 0.48
    end

    -- Count down injection
    if stagger.steerTimer > 0 then
        stagger.steerTimer = stagger.steerTimer - dt
        if stagger.steerTimer <= 0 then
            stagger.steerMod   = 0.0
            stagger.steerTimer = 0.0
        end
    end
end

-- ============================================================================
-- AMBIENT WHISPER -- text only, no face
-- Brief, ambient, gone before they are sure they saw it.
-- Different screen position per category.
-- ============================================================================

local whisper = {
    active   = false,
    widget   = nil,
    timer    = 0.0,
    duration = 0.0,
    col      = { r=1, g=1, b=1 },
    cooldowns= {},
}

local whisperLines = {
    dark_side = {
        "come to the dark side...",
        "see that person? i think they want a closer look at your vehicle...",
        "one more... just one more...",
        "they all think they can stop you.",
        "night city belongs to those who take it.",
        "the line is right there. you could...",
        "everyone has a price. what is yours?",
        "that pedestrian is really testing your patience...",
        "you know what the machine wants.",
    },
    pleasant = {
        "i love cruisin like this. how about you?",
        "night city is beautiful when you stop fighting it.",
        "this is what it is all about.",
        "just you and the road.",
        "the engine sounds happy.",
        "breathe. you have earned this.",
        "this is what clean driving feels like.",
        "nobody can touch you right now.",
        "ride it forever.",
    },
    police = {
        "let's burn some rubber, choom!",
        "c'mon, let's not let the girls down -- everyone's watching!",
        "FLOOR IT. they cannot keep up.",
        "watson never looked so good in the rear view.",
        "this is what the machine was built for.",
        "go go go go GO!",
        "show them what a real driver looks like!",
        "Mahno, we are NOT stopping here.",
    },
    highway = {
        "highway hypnosis setting in... good.",
        "the road becomes you.",
        "miles just disappear, don't they.",
        "this is the zen of the machine.",
        "night city at speed. nothing like it.",
        "your hands know what to do. your mind is free.",
        "let it carry you.",
    },
}

local whisperCooldowns = {
    dark_side = 45.0,
    pleasant  = 30.0,
    police    = 18.0,
    highway   = 60.0,
}

local whisperColors = {
    dark_side = { r=0.9,  g=0.08, b=0.08 },
    pleasant  = { r=0.25, g=0.92, b=0.42 },
    police    = { r=1.0,  g=0.72, b=0.08 },
    highway   = { r=0.38, g=0.72, b=1.0  },
}

-- whisperSetup built lazily inside whisper() -- inkEAnchor not available at require time
local function getWhisperSetup(category)
    local s = {
        dark_side = { inkEAnchor.BottomLeft,  {0.0, 1.0}, function(h) return inkMargin.new({left=h*0.04, top=0, right=0, bottom=h*0.12}) end, 15 },
        pleasant  = { inkEAnchor.TopCenter,   {0.5, 0.0}, function(h) return inkMargin.new({left=0, top=h*0.07, right=0, bottom=0}) end, 15 },
        police    = { inkEAnchor.CenterRight, {1.0, 0.5}, function(h) return inkMargin.new({left=0, top=0, right=h*0.04, bottom=0}) end, 16 },
        highway   = { inkEAnchor.Centered,    {0.5, 0.5}, function(h) return inkMargin.new({left=0, top=h*0.12, right=0, bottom=0}) end, 14 },
    }
    return s[category]
end

function VoiceSystem.whisper(category)
    if whisper.active then return end
    local cd = whisper.cooldowns[category] or 0
    if cd > 0 then return end

    local pool = whisperLines[category]
    if not pool or #pool == 0 then return end

    local setup = getWhisperSetup(category)
    if not setup then return end

    local text = pool[math.random(1, #pool)]
    local col  = whisperColors[category] or { r=1, g=1, b=1 }

    local w = makeWidget("V12Whisper", setup[4],
        setup[1], setup[2], setup[3])
    if not w then return end

    whisper.widget   = w
    whisper.timer    = 0.0
    whisper.duration = 2.2 + math.random() * 1.6
    whisper.col      = col
    whisper.active   = true

    pcall(function() w:SetText(text); w:SetVisible(true) end)
    whisper.cooldowns[category] = whisperCooldowns[category] or 30.0
    print("[V12 Voice] [" .. category .. "] " .. text)
end

local function updateWhisper(dt)
    for cat, cd in pairs(whisper.cooldowns) do
        whisper.cooldowns[cat] = math.max(0.0, cd - dt)
    end

    if not whisper.active then return end
    whisper.timer = whisper.timer + dt

    local col     = whisper.col
    local fadeIn  = 0.35
    local fadeOut = 0.55
    local alpha

    if whisper.timer < fadeIn then
        alpha = whisper.timer / fadeIn
    elseif whisper.timer < whisper.duration - fadeOut then
        alpha = 1.0
    elseif whisper.timer < whisper.duration then
        alpha = (whisper.duration - whisper.timer) / fadeOut
    else
        whisper.active = false
        removeWidget("V12Whisper")
        whisper.widget = nil
        return
    end

    if whisper.widget then
        pcall(function()
            whisper.widget:SetTintColor(HDRColor.new({
                Red   = col.r,
                Green = col.g,
                Blue  = col.b,
                Alpha = alpha * 0.86,
            }))
        end)
    end
end

-- ============================================================================
-- HIGHWAY HYPNOSIS DETECTOR
-- 30s sustained speed within 20km/h variance, minimal steering.
-- Stacks with each sustained window. Resets on hard input.
-- Grants DFNerve buff + pleasant whisper on each stack.
-- ============================================================================

local highway = {
    sustainTimer = 0.0,
    stackCount   = 0,
    lastSpeed    = 0.0,
    cooldown     = 0.0,
    minSpeed     = 80.0,
    variance     = 20.0,
    steerThresh  = 0.18,
    sustainGoal  = 30.0,
}

function VoiceSystem.updateHighway(dt, speed, steerInput)
    if highway.cooldown > 0 then
        highway.cooldown = highway.cooldown - dt
        return
    end

    local spd   = math.abs(speed or 0)
    local speedOk = (spd >= highway.minSpeed)
    local varOk   = (math.abs(spd - highway.lastSpeed) <= highway.variance * dt * 4)
    local steerOk = (math.abs(steerInput or 0) < highway.steerThresh)

    highway.lastSpeed = spd

    if speedOk and varOk and steerOk then
        highway.sustainTimer = highway.sustainTimer + dt
        if highway.sustainTimer >= highway.sustainGoal then
            highway.sustainTimer = 0.0
            highway.stackCount   = highway.stackCount + 1
            highway.cooldown     = 50.0
            pcall(function()
                local dfs = Game.GetScriptableSystemsContainer():Get("DarkFuture.Needs.DFNerveSystem")
                if dfs then
                    local bonus = math.min(20.0, 6.0 + highway.stackCount * 2.0)
                    dfs:QueueContextuallyDelayedNeedValueChange(bonus, true)
                end
            end)
            VoiceSystem.whisper("highway")
            print("[V12 Voice] Highway hypnosis stack " .. highway.stackCount
                .. " -- nerve bonus applied.")
        end
    else
        if math.abs(steerInput or 0) > 0.55 or (spd > 0 and spd < highway.minSpeed * 0.5) then
            highway.sustainTimer = 0.0
            highway.stackCount   = 0
        else
            highway.sustainTimer = math.max(0.0, highway.sustainTimer - dt * 0.4)
        end
    end
end

-- ============================================================================
-- TIP SEQUENCE -- fires on first x10 streak ever
-- Instructional flipbook: H-gate layout, how to shift, tips, sign-off.
-- Appears bottom-right, unobtrusive, cycled through automatically.
-- ============================================================================

local tip = {
    active     = false,
    fired      = false,
    frame      = 0,
    frameTimer = 0.0,
    pulse      = 0.0,
    widget     = nil,
}

local tipFrames = {
    {
        dur  = 4.5,
        text = "  NUMPAD = H-GATE\n\n  [7]=1st  [8]=2nd  [9]=3rd\n\n  [4]=4th  [5]=5th  [6]=6th\n\n  [1]=7th  [2]=8th  [3]=9th\n\n  [0] = NEUTRAL",
    },
    {
        dur  = 4.5,
        text = "  HOW TO SHIFT\n\n  1. HOLD LEFT CTRL\n     (CLUTCH)\n\n  2. PRESS NUMPAD GEAR\n\n  3. RELEASE CTRL\n\n  THAT IS ALL.",
    },
    {
        dur  = 4.5,
        text = "  GEAR STUCK?\n\n  REVERSE. THEN FIRST.\n  WORKS EVERY TIME.\n\n  F KEY = CYCLE MODE\n  (MAIN F -- NOT NUMPAD)\n\n  BLUE IS NOT DEFEAT.\n  BLUE IS STRATEGY.",
    },
    {
        dur  = 3.5,
        text = "  TEN SHIFTS. CLEAN.\n\n  YOU HAVE EARNED THIS.\n\n  THE GEARBOX IS YOURS.\n\n  -- V12 RD911",
    },
}

function VoiceSystem.onFirstStreak10()
    if tip.fired or tip.active then return end
    tip.fired  = true
    tip.active = true
    tip.frame  = 0
    tip.pulse  = 0.0
    tip.frameTimer = 0.0

    tip.widget = makeWidget("V12Tip", 15,
        inkEAnchor.BottomRight, {1.0, 1.0},
        function(h) return inkMargin.new({left=0, top=0, right=h*0.02, bottom=h*0.08}) end)

    if tip.widget then
        pcall(function()
            tip.widget:SetText(tipFrames[1].text)
            tip.widget:SetVisible(true)
        end)
    end
    print("[V12 Voice] Tip sequence -- first x10 streak.")
end

local function updateTip(dt)
    if not tip.active then return end
    tip.pulse      = tip.pulse + dt
    tip.frameTimer = tip.frameTimer + dt

    local fd = tipFrames[tip.frame + 1]
    if not fd then
        tip.active = false
        removeWidget("V12Tip")
        tip.widget = nil
        return
    end

    if tip.frameTimer >= fd.dur then
        tip.frame     = tip.frame + 1
        tip.frameTimer= 0.0
        fd = tipFrames[tip.frame + 1]
        if not fd then
            tip.active = false
            removeWidget("V12Tip")
            tip.widget = nil
            return
        end
    end

    if tip.widget then
        local p = tip.frameTimer / fd.dur
        local alpha
        if p < 0.10 then alpha = p / 0.10
        elseif p > 0.85 then alpha = (1.0 - p) / 0.15
        else alpha = 1.0 end

        local scan = 0.88 + math.sin(tip.pulse * 3.8) * 0.08
        pcall(function()
            tip.widget:SetText(fd.text)
            tip.widget:SetTintColor(HDRColor.new({
                Red   = 0.18,
                Green = 0.82,
                Blue  = 0.95,
                Alpha = alpha * scan * 0.88,
            }))
            tip.widget:SetVisible(true)
        end)
    end
end

-- ============================================================================
-- GHOST IN THE MACHINE
-- The rarest easter egg. 50 consecutive clean Red shifts in one session.
-- White/silver face. Calmer. More knowing. Aware of itself.
-- Never documented. Never announced. Just there for whoever finds it.
-- "Ghost in the Machine" -- the mod itself, speaking.
-- ============================================================================

local ghost = {
    active       = false,
    phase        = 0,
    phaseTimer   = 0.0,
    pulse        = 0.0,
    faceWidget   = nil,
    msgWidget    = nil,
    msgIndex     = 0,
    msgTimer     = 0.0,
    mouthIdx     = 1,
    mouthTimer   = 0.0,
    blinkTimer   = 0.0,
    blinkOpen    = true,
    cleanStreak  = 0,
    sessionShifts= 0,
    fired        = false,
}

-- Ghost face uses + instead of # -- calmer, more precise, less aggressive
local ghostFace = {
    "     . . . . . . . . .     ",
    "   . . . . . . . . . . .   ",
    "   . + + . . . . + + . .   ",
    "   . + + . . . . + + . .   ",
    "   . + + . . . . + + . .   ",
    "   . . . . + . . . . . .   ",
    "   . . . . . . . . . . .   ",
    "   . + + + + + + + + . .   ",
    "   . . . . . . . . . . .   ",
    "   . . + + + + + + . . .   ",
    "     . . . . . . . . .     ",
}

local ghostMouths = {
    "   . + + + + + + + + . .   ",
    "   . . + + + + + + . . .   ",
    "   . + . . . . . . + . .   ",
    "   . . . + + + + . . . .   ",
    "   . + + + + + + + + . .   ",
    "   . . . . . . . . . . .   ",
    "   . + . + . + . + . + .   ",
    "   . . + + . . + + . . .   ",
}

-- Ghost messages -- the machine speaks about what it knows
-- References sessionShifts so each appearance is personal
local function buildGhostMessages(sessionShifts)
    return {
        { text = "YOU HAVE BEEN HERE A WHILE.",               delay=1.6, r=0.95, g=0.95, b=1.0 },
        { text = "FIFTY SHIFTS. CLEAN.",                      delay=1.4, r=0.95, g=0.95, b=1.0 },
        { text = string.format("%d TOTAL THIS SESSION.", sessionShifts),
                                                               delay=1.3, r=0.70, g=0.82, b=1.0 },
        { text = "THE GEARBOX KNOWS YOUR HANDS NOW.",         delay=1.7, r=0.95, g=0.95, b=1.0 },
        { text = "FEW FIND THIS.",                            delay=1.2, r=0.70, g=0.82, b=1.0 },
        { text = "YOU DID.",                                  delay=1.0, r=0.70, g=0.82, b=1.0 },
        { text = "WE DON'T TALK ABOUT THIS TO OTHERS.",      delay=1.9, r=0.95, g=0.95, b=1.0 },
        { text = "DRIVE WELL.",                               delay=1.2, r=0.95, g=0.95, b=1.0 },
        { text = "I AM ALWAYS HERE.",                         delay=1.5, r=0.70, g=0.82, b=1.0 },
        { text = "-- THE MACHINE",                            delay=2.8, r=0.50, g=0.65, b=1.0 },
    }
end

local ghostMessages = {}

local function buildGhostFaceText(mouthIdx, blinkOpen)
    local lines = {}
    for i, row in ipairs(ghostFace) do
        local line = row
        if (i == 4 or i == 5) and not blinkOpen then
            line = "   . . . . . . . . . . .   "
        end
        if i == 8 then
            line = ghostMouths[((mouthIdx - 1) % #ghostMouths) + 1]
        end
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

local function fireGhost()
    if ghost.active or ghost.fired then return end
    ghost.fired      = true
    ghost.active     = true
    ghost.phase      = 1
    ghost.phaseTimer = 0.0
    ghost.pulse      = 0.0
    ghost.msgIndex   = 0
    ghost.msgTimer   = 0.0
    ghost.mouthIdx   = 1
    ghost.mouthTimer = 0.0
    ghost.blinkTimer = 0.0
    ghost.blinkOpen  = true

    ghostMessages = buildGhostMessages(ghost.sessionShifts)

    ghost.faceWidget = makeWidget("V12GhostFace", 22,
        inkEAnchor.Centered, {0.5, 0.5},
        function(h) return inkMargin.new({left=0, top=-h*0.1, right=0, bottom=0}) end)
    ghost.msgWidget  = makeWidget("V12GhostMsg", 17,
        inkEAnchor.Centered, {0.5, 0.0},
        function(h) return inkMargin.new({left=0, top=h*0.58, right=0, bottom=0}) end)

    print("[V12 Ghost] The machine speaks. "
        .. ghost.sessionShifts .. " shifts this session.")
end

function VoiceSystem.onCleanRedShift()
    if ghost.fired then return end
    ghost.cleanStreak   = ghost.cleanStreak + 1
    ghost.sessionShifts = ghost.sessionShifts + 1
    if ghost.cleanStreak >= 50 then
        fireGhost()
    end
end

function VoiceSystem.onRedFailGhost()
    ghost.cleanStreak = 0
end

local function updateGhost(dt)
    if not ghost.active then return end
    ghost.pulse      = ghost.pulse + dt
    ghost.phaseTimer = ghost.phaseTimer + dt

    -- Blink -- slower, more deliberate than the initiation face
    ghost.blinkTimer = ghost.blinkTimer + dt
    if ghost.blinkOpen and ghost.blinkTimer > 4.2 then
        ghost.blinkOpen  = false
        ghost.blinkTimer = 0.0
    elseif not ghost.blinkOpen and ghost.blinkTimer > 0.18 then
        ghost.blinkOpen  = true
        ghost.blinkTimer = 0.0
    end

    -- Mouth -- slow and deliberate
    ghost.mouthTimer = ghost.mouthTimer + dt
    if ghost.mouthTimer >= 0.32 then
        ghost.mouthTimer = 0.0
        ghost.mouthIdx   = (ghost.mouthIdx % #ghostMouths) + 1
    end

    -- Gentle float
    local floatY = math.sin(ghost.pulse * 0.85) * 9.0

    -- Silver/white scanline
    local scan = 0.82 + math.sin(ghost.pulse * 5.2) * 0.08

    -- Phase 1: materialize (1.8s)
    if ghost.phase == 1 then
        local progress = ghost.phaseTimer / 1.8
        local alpha    = math.min(1.0, progress * 1.9) * scan

        if ghost.faceWidget then
            pcall(function()
                ghost.faceWidget:SetText(buildGhostFaceText(ghost.mouthIdx, ghost.blinkOpen))
                ghost.faceWidget:SetTintColor(HDRColor.new({
                    Red=0.88, Green=0.93, Blue=1.0, Alpha=alpha
                }))
                ghost.faceWidget:SetMargin(inkMargin.new({
                    left=0, top=-1080*0.1 + floatY, right=0, bottom=0
                }))
                ghost.faceWidget:SetVisible(true)
            end)
        end

        if ghost.phaseTimer >= 1.8 then
            ghost.phase     = 2
            ghost.phaseTimer= 0.0
            ghost.msgIndex  = 0
            ghost.msgTimer  = 0.0
            if ghost.msgWidget then ghost.msgWidget:SetVisible(true) end
        end

    -- Phase 2: messages
    elseif ghost.phase == 2 then
        if ghost.faceWidget then
            pcall(function()
                ghost.faceWidget:SetText(buildGhostFaceText(ghost.mouthIdx, ghost.blinkOpen))
                ghost.faceWidget:SetTintColor(HDRColor.new({
                    Red=0.88, Green=0.93, Blue=1.0, Alpha=scan
                }))
                ghost.faceWidget:SetMargin(inkMargin.new({
                    left=0, top=-1080*0.1 + floatY, right=0, bottom=0
                }))
            end)
        end

        ghost.msgTimer = ghost.msgTimer + dt
        if ghost.msgIndex < #ghostMessages then
            local cur = ghostMessages[ghost.msgIndex + 1]
            if ghost.msgTimer >= (cur and cur.delay or 1.5) then
                ghost.msgIndex = ghost.msgIndex + 1
                ghost.msgTimer = 0.0
                local msg = ghostMessages[ghost.msgIndex]
                if msg and ghost.msgWidget then
                    pcall(function()
                        ghost.msgWidget:SetText(msg.text)
                        ghost.msgWidget:SetTintColor(HDRColor.new({
                            Red=msg.r, Green=msg.g, Blue=msg.b, Alpha=1.0
                        }))
                    end)
                end
            end
        else
            if ghost.msgTimer >= 2.8 then
                ghost.phase     = 3
                ghost.phaseTimer= 0.0
            end
        end

    -- Phase 3: fade out (1.4s)
    elseif ghost.phase == 3 then
        local alpha = math.max(0.0, 1.0 - ghost.phaseTimer / 1.4)
        if ghost.faceWidget then
            pcall(function()
                ghost.faceWidget:SetTintColor(HDRColor.new({
                    Red=0.88, Green=0.93, Blue=1.0, Alpha=alpha * 0.9
                }))
            end)
        end
        if ghost.msgWidget then
            pcall(function()
                ghost.msgWidget:SetTintColor(HDRColor.new({
                    Red=0.7, Green=0.82, Blue=1.0, Alpha=alpha
                }))
            end)
        end
        if ghost.phaseTimer >= 1.4 then
            removeWidget("V12GhostFace")
            removeWidget("V12GhostMsg")
            ghost.faceWidget = nil
            ghost.msgWidget  = nil
            ghost.active     = false
            ghost.phase      = 0
            print("[V12 Ghost] The machine is silent again.")
        end
    end
end

-- ============================================================================
-- MIDNIGHT DRIVE EASTER EGG
-- Driving Red mode when in-game clock hits 00:00.
-- Soft ambient text. Never mentioned anywhere.
-- Just there for whoever finds it.
-- ============================================================================

local midnight = {
    lastHour = -1,
    fired    = false,
    handle   = nil,
}

local function checkMidnight(isInVehicle, isRedMode)
    if not isInVehicle or not isRedMode then return end
    pcall(function()
        local t     = Game.GetTimeSystem():GetGameTime()
        local hours = t:Hours()
        local mins  = t:Minutes()

        if hours == midnight.lastHour then return end
        midnight.lastHour = hours

        if hours ~= 0 then
            midnight.fired = false
            return
        end

        if midnight.fired then return end
        midnight.fired = true

        -- Soft text, top center, fades in and out over 6 seconds
        local w = makeWidget("V12Midnight", 16,
            inkEAnchor.TopCenter, {0.5, 0.0},
            function(h) return inkMargin.new({left=0, top=h*0.07, right=0, bottom=0}) end)

        if not w then return end

        pcall(function()
            w:SetText("night city never sleeps. neither do you.")
            w:SetTintColor(HDRColor.new({Red=0.38, Green=0.58, Blue=1.0, Alpha=0.0}))
            w:SetVisible(true)
        end)

        local elapsed = 0.0
        local eng = getEng()
        if eng then
            midnight.handle = eng.SetInterval(0.016, function()
                elapsed = elapsed + 0.016
                local alpha
                if elapsed < 1.2 then
                    alpha = elapsed / 1.2
                elseif elapsed < 4.0 then
                    alpha = 1.0
                elseif elapsed < 6.0 then
                    alpha = (6.0 - elapsed) / 2.0
                else
                    alpha = 0.0
                end
                pcall(function()
                    w:SetTintColor(HDRColor.new({
                        Red=0.38, Green=0.58, Blue=1.0, Alpha=alpha * 0.82
                    }))
                end)
                if elapsed >= 6.0 then
                    removeWidget("V12Midnight")
                    local e2 = getEng()
                    if e2 and midnight.handle then
                        e2.ClearTimer(midnight.handle)
                        midnight.handle = nil
                    end
                end
            end)
        end
        print("[V12 Ghost] Midnight easter egg -- welcome to 00:00.")
    end)
end

-- ============================================================================
-- POLICE CONTACT TRIGGER
-- Call from init.lua when police stars become active (not just initiated).
-- ============================================================================

local policeState = {
    wasWanted   = false,
    cooldown    = 0.0,
}

function VoiceSystem.updatePolice(dt, wantedLevel)
    if policeState.cooldown > 0 then
        policeState.cooldown = policeState.cooldown - dt
    end

    local isWanted = (wantedLevel and wantedLevel > 0)

    if isWanted and not policeState.wasWanted and policeState.cooldown <= 0 then
        VoiceSystem.whisper("police")
        policeState.cooldown = 90.0
    end

    policeState.wasWanted = isWanted
end

-- ============================================================================
-- DARK SIDE TRIGGER
-- Call from init.lua when nerve/humanity is actively dropping.
-- ============================================================================

local darkSideCooldown = 0.0

function VoiceSystem.onNerveDropping(dt)
    darkSideCooldown = darkSideCooldown - dt
    if darkSideCooldown <= 0 then
        if math.random() < 0.15 then  -- 15% chance each call
            VoiceSystem.whisper("dark_side")
            darkSideCooldown = 55.0 + math.random() * 30.0
        else
            darkSideCooldown = 8.0
        end
    end
end

-- ============================================================================
-- PLEASANT TRIGGER
-- Call from init.lua when nerve/humanity is full or clean cruise active.
-- ============================================================================

local pleasantCooldown = 0.0

function VoiceSystem.onNerveFull(dt)
    pleasantCooldown = pleasantCooldown - dt
    if pleasantCooldown <= 0 then
        if math.random() < 0.12 then
            VoiceSystem.whisper("pleasant")
            pleasantCooldown = 65.0 + math.random() * 40.0
        else
            pleasantCooldown = 10.0
        end
    end
end

-- ============================================================================
-- MAIN UPDATE
-- Call from init.lua onUpdate every frame.
-- ============================================================================
function VoiceSystem.update(dt, params)
    params = params or {}

    updateDrunkVision(dt)
    updateStagger(dt)
    updateWhisper(dt)
    updateGhost(dt)
    updateTip(dt)

    if params.isInVehicle then
        VoiceSystem.updateHighway(dt, params.speed or 0, params.steerInput or 0)
        checkMidnight(params.isInVehicle, params.isRedMode)
        VoiceSystem.updatePolice(dt, params.wantedLevel)
    end

    -- Drunk level fed from thermalV12
    local drunk = params.drunkLevel or 0.0
    VoiceSystem.setDrunkLevel(drunk)
    VoiceSystem.setStaggerLevel(drunk)
end

-- ============================================================================
-- INIT
-- ============================================================================
function VoiceSystem.init()
    ghost.cleanStreak   = 0
    ghost.fired         = false
    ghost.sessionShifts = 0
    tip.fired           = false
    midnight.fired      = false
    midnight.lastHour   = -1
    darkSideCooldown    = 30.0  -- brief grace period on load
    pleasantCooldown    = 60.0
    print("[V12 Voice] voiceSystem.lua initialised.")
end

-- ============================================================================
-- TEST API -- console access for development
-- ============================================================================
function VoiceSystem.testWhisper(cat)
    whisper.cooldowns[cat] = 0
    VoiceSystem.whisper(cat or "dark_side")
end

function VoiceSystem.testGhost()
    ghost.fired         = false
    ghost.active        = false
    ghost.cleanStreak   = 50
    ghost.sessionShifts = 137
    fireGhost()
end

function VoiceSystem.testMidnight()
    midnight.fired = false
    midnight.lastHour = -1
    -- Manually call with fake conditions
    print("[V12 Ghost] Midnight test -- watch for ambient text.")
end

function VoiceSystem.testTip()
    tip.fired  = false
    tip.active = false
    VoiceSystem.onFirstStreak10()
end

return VoiceSystem