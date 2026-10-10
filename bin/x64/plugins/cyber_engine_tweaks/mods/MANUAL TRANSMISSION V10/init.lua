-- ============================================================================
-- MANUAL TRANSMISSION V12  --  RACERS DELIGHT
-- Built on the shoulders of the original V10 by its author. Green mode
-- preserved 1:1 as a tribute to that foundation.
-- Racer layer: Blue (Shiftronic) + Red (H-Pattern) + RPM/Heat GUI
-- Engine: 0-Engine runtime (v0.18.6+), replaces Cron throughout
-- New: V12 Thermal Immersion system (thermalV12.lua) -- stress, adrenaline,
--      clutch heat, stall detection -- all publishing to 0-Engine shared bus
-- ============================================================================

local GameUI      = require("modules/psiberx/GameUI")
local config      = require("modules/keanuWheeze/config")
local inputManager= require("modules/keanuWheeze/inputManager")
local utils       = require("modules/utils")
local Clutch      = require("modules/clutch")
local Gearbox     = require("modules/gearbox")

-- 0-Engine resolved in onInit -- GetMod not available at require() time
local eng = nil

-- V12 Thermal Immersion system
local okTherm, thermalV12 = pcall(require, "modules/thermalV12")
if not okTherm then
    thermalV12 = nil
    print("[V12 Racer] WARNING: thermalV12.lua not found -- thermal system disabled.")
end

-- V12 Secret Initiation Sequence
local okIntro, introSeq = pcall(require, "modules/introSequence")
if not okIntro then
    introSeq = nil
    print("[V12 Racer] WARNING: introSequence.lua not found -- initiation disabled.")
end

-- V12 Voice and Ambient System
local okVoice, voiceSystem = pcall(require, "modules/voiceSystem")
if not okVoice then
    voiceSystem = nil
    print("[V12 Racer] WARNING: voiceSystem.lua not found -- ambient system disabled.")
end

-- gearboxFeel retired -- thermalV12 is its replacement
local gearboxFeel = nil

-- Blue + Red side loader. Never calls Gearbox.SetLock -- Green keeps the lock.
local okSM, ShiftModes = pcall(require, "modules/shiftModes")
if not okSM then
    ShiftModes = nil
    print("[V12 Racer] WARNING: shiftModes.lua failed to load -- " .. tostring(ShiftModes))
end

local VEHICLE_MODES_PATH = "vehicle_modes.json"
local CONFIG_PATH        = "config.json"
local settingsPath       = "/mt_v10"
local bbVehicleDef       = nil

local vehicleModes = {}
if config.fileExists(VEHICLE_MODES_PATH) then
    vehicleModes = config.loadFile(VEHICLE_MODES_PATH) or {}
end

local CONFIG_VERSION = 1

local defaultSettings = {
    config_version          = CONFIG_VERSION,
    enabled                 = true,
    isManualMode            = false,
    mt_per_vehicle_memory   = false,
    mt_show_fpp             = true,
    mt_show_tpp             = true,
    mt_use_mouse_wheel      = false,
    mt_require_clutch       = false,
    mt_ignore_pad           = false,
    mt_toggle_key           = "IK_M",
    mt_upshift_key          = "IK_Up",
    mt_downshift_key        = "IK_Down",
    mt_clutch_key           = "IK_LControl",
    mt_neutral_key          = "IK_G",
    mt_upshift_pad          = "IK_Pad_A_CROSS",
    mt_downshift_pad        = "IK_Pad_X_SQUARE",
    mt_clutch_axis          = "IK_Pad_LeftAxisY",
    mt_clutch_slip_enter    = 0.15,
    mt_clutch_neutral_enter = 0.80,
    mt_clutch_reengage_exit = 0.65,
    -- V10 Racer
    mt_racing_enabled       = true,
    -- FIX 2026-08-04 (D): NumPad "." restored as the mode-cycle key (V10 muscle
    -- memory). Engine reports this key as IK_NumPeriod -- confirmed from
    -- config.json files, which nativeSettings writes using the name the game
    -- itself reports. The OG source string "IK_NumPadPeriod" is NOT a real
    -- EInputKey name and never matched anything.
    mt_racing_toggle_key    = "IK_NumPeriod",
    mt_gear1_key            = "IK_NumPad4",
    mt_gear2_key            = "IK_NumPad1",
    mt_gear3_key            = "IK_NumPad5",
    mt_gear4_key            = "IK_NumPad2",
    mt_gear5_key            = "IK_NumPad6",
    mt_gear6_key            = "IK_NumPad3",
    mt_racing_neutral_key   = "IK_NumPad0",
    mt_gear7_key            = "IK_NumPad0",
    mt_perpetual_neutral_key = "IK_Comma",
    -- ADDED 2026-08-04: Red H-pattern reverse gate. NumPad7 sits up-left of the
    -- 4/5/6 + 1/2/3 gate, the classic dogleg reverse position. Only reachable
    -- from Neutral, clutch held, under 2.0 speed. Not used by any other bind.
    -- Config gets this key added automatically by the defaults loop below.
    mt_gear_reverse_key     = "IK_NumPad7",
    mt_reward_interval      = 2,
    mt_audio_rewards        = true,
    mt_humanity_enabled     = false,
    -- Audio volumes
    mt_vol_failed_shift     = 0.65,
    mt_vol_small_reward     = 0.65,
    mt_vol_level_10_reward  = 0.65,
    mt_vol_level_20_reward  = 0.65,
    -- Blinkers
    mt_blinker_left_key     = "IK_Left",
    mt_blinker_right_key    = "IK_Right",
    mt_blinker_hazard_key   = "IK_H",
    mt_blinkers_enabled     = true,
}

local settings = {}
if config.fileExists(CONFIG_PATH) then
    settings = config.loadFile(CONFIG_PATH) or {}
end

local needsSave  = false
local oldVersion = settings.config_version or 0
if oldVersion < CONFIG_VERSION then
    if oldVersion < 1 and settings.mt_neutral_key == "IK_LControl" then
        settings.mt_neutral_key = "IK_G"
    end
    if settings.mt_clutch_key == "IK_LShift" then
        settings.mt_clutch_key = "IK_LControl"
        needsSave = true
    end
    settings.config_version = CONFIG_VERSION
    needsSave = true
end
for k, v in pairs(defaultSettings) do
    if settings[k] == nil then settings[k] = v; needsSave = true end
end
if type(settings.mt_show_fpp)             ~= "boolean" then settings.mt_show_fpp = true end
if type(settings.mt_show_tpp)             ~= "boolean" then settings.mt_show_tpp = true end
if type(settings.mt_ignore_pad)           ~= "boolean" then settings.mt_ignore_pad = false end
if type(settings.mt_use_mouse_wheel)      ~= "boolean" then settings.mt_use_mouse_wheel = false end
if type(settings.mt_clutch_axis)          ~= "string"  then settings.mt_clutch_axis = "IK_Pad_LeftAxisY" end
if type(settings.mt_clutch_slip_enter)    ~= "number"  then settings.mt_clutch_slip_enter = 0.30 end
if type(settings.mt_clutch_neutral_enter) ~= "number"  then settings.mt_clutch_neutral_enter = 0.65 end
if type(settings.mt_clutch_reengage_exit) ~= "number"  then settings.mt_clutch_reengage_exit = 0.45 end
settings.mt_upshift_pad   = "IK_Pad_A_CROSS"
settings.mt_downshift_pad = "IK_Pad_X_SQUARE"
if needsSave then config.saveFile(CONFIG_PATH, settings) end

-- ============================================================================
-- STATE
-- ============================================================================
local state = {
    isManualMode        = settings.isManualMode or false,
    isLocked            = false,
    persistentNeutralUI = false,
    currentGear         = -1,
    targetGear          = -1,
    inVehicle           = false,
    playerVehicle       = nil,
    vehicleStats        = nil,
    vehicleBlackboard   = nil,
    shifting            = false,
    shiftTimeout        = 0,
    speed               = 0,
    lastGearInteger     = -999,
    lastManualState     = nil,
    isFPP               = false,
    keyStates           = {},
    keyHoldTimes        = {},
    entryGrace          = 0,
    clutchAmount        = 0.0,
    clutchHoldTimer     = 0.0,
    clutchMode          = "engaged",
    lastClutchMode      = "engaged",
    lastUIClutchMode    = "engaged",
    isAccelerating      = false,
    isDecelerating      = false,
    currentVehicleKey   = nil,
    mouseWheelUpshift   = false,
    mouseWheelDownshift = false,
    ghostGear           = nil,
    -- V10 Racer additions
    raceMode            = 0,
    raceStreak          = 0,
    rejectFlash         = 0,
    goodFlash           = 0,
    kickFlash           = 0,
    blueAutoArmed       = true,
    blueIntentHigh      = false,
    blueIntentLow       = false,
    rpmOccupancy        = 0,
    healthPulse         = 0,
    -- Blinker state
    blinkerLeft         = false,
    blinkerRight        = false,
    blinkerHazard       = false,
    blinkerTimer        = 0,
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
local function checkInput(keyName)
    if not keyName or keyName == "" then return false end
    local isDown  = (inputManager.activeKeys[keyName] ~= nil)
    local wasDown = state.keyStates[keyName] or false
    state.keyStates[keyName] = isDown
    return isDown and not wasDown
end

local function checkTap(keyName, dt, maxHoldTime)
    if not keyName or keyName == "" then return false, false end
    local isDown      = (inputManager.activeKeys[keyName] ~= nil)
    local wasDown     = state.keyStates[keyName] or false
    local isJustPress = isDown and not wasDown
    if isJustPress then
        state.keyHoldTimes[keyName] = 0
    elseif isDown then
        state.keyHoldTimes[keyName] = (state.keyHoldTimes[keyName] or 0) + dt
    end
    local tapTriggered = false
    if not isDown and wasDown then
        local holdTime = state.keyHoldTimes[keyName] or 0
        if holdTime <= maxHoldTime then tapTriggered = true end
    end
    state.keyStates[keyName] = isDown
    return isJustPress, tapTriggered
end

local function isHoldingInput(keyName)
    if not keyName or keyName == "" then return false end
    return inputManager.activeKeys[keyName] ~= nil
end

local function saveVehicleModes()
    config.saveFile(VEHICLE_MODES_PATH, vehicleModes)
end

local function getVehicleKey(vehicle)
    if not vehicle then return nil end
    local ok, rec = pcall(function() return vehicle:GetRecord() end)
    if ok and rec then return tostring(rec:GetID()) end
    return nil
end

local function HandlePedalAction(action, actionValue)
    if ListenerAction.IsAxisChangeAction(action) then
        return (actionValue > 0.05)
    else
        if ListenerAction.IsButtonJustPressed(action)   then return true  end
        if ListenerAction.IsButtonJustReleased(action)  then return false end
    end
    return nil
end

-- ============================================================================
-- V12 RACER HELPERS
-- ============================================================================
local raceTierMax = { 3, 7, 10, 12 }

local function dropOneRaceTier(streak)
    local idx = 1
    for i, maxv in ipairs(raceTierMax) do
        if streak <= maxv then idx = i; break end
    end
    if idx <= 1 then return 0 end
    return raceTierMax[idx - 1]
end

local function isGearProperForSpeed(targetGear)
    if targetGear == -1 or targetGear == 0 then return true end
    if not state.vehicleStats or not state.vehicleStats.gears then return true end
    local gd = state.vehicleStats.gears[targetGear]
    if not gd then return true end
    local spd = math.abs(state.speed or 0)
    if gd.minSpeed and spd < gd.minSpeed             then return false end
    if gd.maxSpeed and spd > gd.maxSpeed * 1.15      then return false end
    return true
end

-- ============================================================================
-- BLINKER SYSTEM
-- ============================================================================
local function triggerVehicleBlinker(direction)
    -- direction: "left" | "right" | "hazard" | "off"
    if not state.playerVehicle then return end
    pcall(function()
        if direction == "left" then
            state.playerVehicle:ToggleLeftTurnSignal()
        elseif direction == "right" then
            state.playerVehicle:ToggleRightTurnSignal()
        elseif direction == "hazard" then
            state.playerVehicle:ToggleHazardWarning()
        end
    end)
end

local function updateBlinkers(dt)
    if not settings.mt_blinkers_enabled or not state.inVehicle then return end

    -- Only check blinker keys when NOT using them for shifting
    -- Left/Right arrows are shift keys in manual mode Green/Blue seq shifting
    -- In Red mode they're not used for shifting so always available
    -- Outside manual mode they're always available
    local leftFree  = not state.isManualMode or state.raceMode == 2
    local rightFree = not state.isManualMode or state.raceMode == 2

    if leftFree and checkInput(settings.mt_blinker_left_key) then
        if state.blinkerHazard then
            state.blinkerHazard = false
            state.blinkerLeft   = false
            state.blinkerRight  = false
            triggerVehicleBlinker("hazard") -- toggle off
        elseif state.blinkerLeft then
            state.blinkerLeft = false
        else
            state.blinkerLeft  = true
            state.blinkerRight = false
        end
        triggerVehicleBlinker("left")
    end

    if rightFree and checkInput(settings.mt_blinker_right_key) then
        if state.blinkerHazard then
            state.blinkerHazard = false
            state.blinkerLeft   = false
            state.blinkerRight  = false
            triggerVehicleBlinker("hazard") -- toggle off
        elseif state.blinkerRight then
            state.blinkerRight = false
        else
            state.blinkerRight = true
            state.blinkerLeft  = false
        end
        triggerVehicleBlinker("right")
    end

    if checkInput(settings.mt_blinker_hazard_key) then
        state.blinkerHazard = not state.blinkerHazard
        state.blinkerLeft   = false
        state.blinkerRight  = false
        triggerVehicleBlinker("hazard")
    end
end

-- ============================================================================
-- AUXILIARY WIDGETS  (RPM dot + Heat dot)
-- ============================================================================
local auxRPMWidget  = nil
local auxHeatWidget    = nil
local auxStressWidget  = nil   -- ghost: stress/nerves indicator
local auxAdrWidget     = nil   -- ghost: adrenaline indicator
local auxBrakeWidget   = nil   -- ghost: brake heat indicator
local auxClutchWidget  = nil   -- vertical clutch bar
local auxInkSystem  = nil
local ghostAboveWidget = nil   -- Green mode: faded gear above current
local ghostBelowWidget = nil   -- Green mode: faded gear below current

local function getAuxInkSystem()
    if not auxInkSystem then auxInkSystem = Game.GetInkSystem() end
    return auxInkSystem
end

local function buildDotWidget(id, xMult, yMult, fontSize)
    local inkSys = getAuxInkSystem()
    if not inkSys then return nil end
    local hudLayer  = inkSys:GetLayer(StringToName("inkHUDLayer"))
    if not hudLayer  then return nil end
    local container = hudLayer:GetVirtualWindow()
    if not container then return nil end
    local wname = StringToName("V10Racer_" .. id)
    local existing = container:GetWidget(wname)
    if existing then container:RemoveChild(existing) end
    local widget = inkText.new()
    widget:SetName(wname)
    widget:SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily")
    widget:SetFontSize(fontSize or 22)
    widget:SetAnchor(inkEAnchor.BottomLeft)
    widget:SetAnchorPoint(0.5, 0.5)
    widget:Reparent(container, -1)
    local w, h = GetDisplayResolution()
    if w and h then
        local xOff = h * xMult
        local yOff = h * yMult
        pcall(function()
            widget:SetMargin(inkMargin.new({ left = xOff, top = 0, right = 0, bottom = yOff }))
        end)
    end
    return widget
end

local ghostGearStr = { [-1]="N", [0]="R", [1]="1", [2]="2", [3]="3", [4]="4", [5]="5", [6]="6" }

local function updateGhostGears(rawGear, raceMode, isFPP, showFPP, showTPP)
    -- Only Green mode gets sequential ghost neighbors
    local shouldShow = (raceMode == 0)
        and (isFPP and showFPP or (not isFPP and showTPP ~= false))
        and type(rawGear) == "number" and rawGear >= 1

    if not shouldShow then
        if ghostAboveWidget and ghostAboveWidget.SetVisible then pcall(function() ghostAboveWidget:SetVisible(false) end) end
        if ghostBelowWidget and ghostBelowWidget.SetVisible then pcall(function() ghostBelowWidget:SetVisible(false) end) end
        return
    end

    if not ghostAboveWidget or not ghostAboveWidget.SetText then
        ghostAboveWidget = buildDotWidget("ghostAbove", 0.303, 0.192, 38)
    end
    if not ghostBelowWidget or not ghostBelowWidget.SetText then
        ghostBelowWidget = buildDotWidget("ghostBelow", 0.303, 0.132, 38)
    end

    local fadeColor = HDRColor.new({ Red = 0.55, Green = 0.85, Blue = 0.55, Alpha = 0.28 })

    local aboveGear = rawGear + 1
    if ghostAboveWidget and ghostAboveWidget.SetText and aboveGear <= 6 then
        pcall(function()
            ghostAboveWidget:SetText(ghostGearStr[aboveGear] or tostring(aboveGear))
            ghostAboveWidget:SetTintColor(fadeColor)
            ghostAboveWidget:SetVisible(true)
        end)
    elseif ghostAboveWidget and ghostAboveWidget.SetVisible then
        pcall(function() ghostAboveWidget:SetVisible(false) end)
    end

    local belowGear = rawGear - 1
    if ghostBelowWidget and ghostBelowWidget.SetText and belowGear >= 1 then
        pcall(function()
            ghostBelowWidget:SetText(ghostGearStr[belowGear] or tostring(belowGear))
            ghostBelowWidget:SetTintColor(fadeColor)
            ghostBelowWidget:SetVisible(true)
        end)
    elseif ghostBelowWidget and ghostBelowWidget.SetVisible then
        pcall(function() ghostBelowWidget:SetVisible(false) end)
    end
end

local function updateAuxWidgets()
    -- Always ensure widgets exist, even when hidden -- so toggle-on is instant
    if not auxRPMWidget    or not auxRPMWidget.SetText    then auxRPMWidget    = buildDotWidget("rpm",      0.318, 0.161, 20) end
    if not auxHeatWidget   or not auxHeatWidget.SetText   then auxHeatWidget   = buildDotWidget("heat",     0.328, 0.161, 20) end
    if not auxClutchWidget or not auxClutchWidget.SetText then auxClutchWidget = buildDotWidget("clutchbar",0.288, 0.155, 14) end

    if not state.inVehicle or not state.isManualMode then
        if auxRPMWidget    and auxRPMWidget.SetVisible    then pcall(function() auxRPMWidget:SetVisible(false)    end) end
        if auxHeatWidget   and auxHeatWidget.SetVisible   then pcall(function() auxHeatWidget:SetVisible(false)   end) end
        if auxClutchWidget and auxClutchWidget.SetVisible then pcall(function() auxClutchWidget:SetVisible(false) end) end
        if auxStressWidget and auxStressWidget.SetVisible then pcall(function() auxStressWidget:SetVisible(false) end) end
        if auxAdrWidget    and auxAdrWidget.SetVisible    then pcall(function() auxAdrWidget:SetVisible(false)    end) end
        if auxBrakeWidget  and auxBrakeWidget.SetVisible  then pcall(function() auxBrakeWidget:SetVisible(false)  end) end
        return
    end

    if auxRPMWidget and auxRPMWidget.SetText then
        local occ  = state.rpmOccupancy or 0
        local rr, rg, rb
        if state.raceMode == 0 then
            rr = 0.05;  rg = 0.3 + occ * 1.2;  rb = 0.05 + occ * 0.3
        elseif state.raceMode == 1 then
            rr = 0.05 + occ * 0.2;  rg = 0.2 + occ * 0.8;  rb = 0.3 + occ * 1.5
        else
            rr = 0.2 + occ * 0.4;  rg = 0.1;  rb = 0.1
        end
        pcall(function()
            auxRPMWidget:SetText("\226\151\143")
            auxRPMWidget:SetTintColor(HDRColor.new({ Red = rr, Green = rg, Blue = rb, Alpha = 1.0 }))
            auxRPMWidget:SetVisible(true)
        end)
    end

    if thermalV12 then
        if auxHeatWidget and auxHeatWidget.SetText then
            local telemetry = nil
            if thermalV12 then
                pcall(function() telemetry = thermalV12.getTelemetry() end)
            end
            -- Heat dot shows clutch temp from V12 thermal system
            local temp = (telemetry and telemetry.clutchTemp) or 20
            local hr, hg, hb = 0.2, 0.4, 1.0
            local pulse = state.healthPulse or 0

            if temp < 40 then
                hr, hg, hb = 0.15, 0.35, 1.0
            elseif temp < 65 then
                local t = (temp - 40) / 25
                hr = 0.15 + t * 0.85; hg = 0.35 + t * 0.65; hb = 1.0 - t * 0.95
            elseif temp < 80 then
                local t = (temp - 65) / 15
                hr = 1.0; hg = 1.0 - t * 0.5; hb = 0.05
            elseif temp < 95 then
                local t = (temp - 80) / 15
                hr = 1.0; hg = 0.5 - t * 0.4; hb = 0.05
            elseif temp < 100 then
                hr, hg, hb = 1.0, 0.05, 0.05
            elseif temp < 112 then
                local flash = math.floor(pulse * 8) % 2
                hr = 1.0; hg = flash == 0 and 0.05 or 1.0; hb = flash == 0 and 0.05 or 1.0
            else
                local flash = math.floor(pulse * 12) % 2
                hr = 1.0; hg = flash == 0 and 0.05 or 0.75; hb = flash == 0 and 0.05 or 0.75
            end
            pcall(function()
                auxHeatWidget:SetText("\226\150\160")
                auxHeatWidget:SetTintColor(HDRColor.new({ Red = hr, Green = hg, Blue = hb, Alpha = 1.0 }))
                auxHeatWidget:SetVisible(true)
            end)
        end
    end

    -- ============================================================
    -- GHOST GUI -- thermal system indicators
    -- Always visible at 15% alpha (ghost anchor for layout testing)
    -- Pop to full color and icon when threshold is crossed
    -- ============================================================
    if thermalV12 then
        local tel = nil
        pcall(function() tel = thermalV12.getTelemetry() end)
        local pulse = state.healthPulse or 0

        -- ---- STRESS indicator (heart icon, yellow->red) ----
        if not auxStressWidget or not auxStressWidget.SetText then
            auxStressWidget = buildDotWidget("stress", 0.342, 0.161, 18)
        end
        if auxStressWidget and auxStressWidget.SetText then
            local stress = (tel and tel.stress) or 0
            local sr, sg, sb, sa
            if stress < 40 then
                -- ghost -- barely visible blue-white
                sr, sg, sb, sa = 0.5, 0.6, 1.0, 0.15
            elseif stress < 70 then
                -- yellow warning
                local t = (stress - 40) / 30
                sr = 0.8 + t * 0.2; sg = 0.8 - t * 0.3; sb = 0.1; sa = 0.5 + t * 0.4
            else
                -- red alert, pulse at critical
                local flash = stress > 85 and (math.floor(pulse * 6) % 2 == 0) and 0.6 or 1.0
                sr, sg, sb, sa = flash, 0.05, 0.05, 1.0
            end
            pcall(function()
                -- Heart unicode: solid block as stand-in, real icon TBD
                auxStressWidget:SetText("\226\153\165")
                auxStressWidget:SetTintColor(HDRColor.new({ Red=sr, Green=sg, Blue=sb, Alpha=sa }))
                auxStressWidget:SetVisible(true)
            end)
        end

        -- ---- ADRENALINE indicator (bolt icon, blue->gold) ----
        if not auxAdrWidget or not auxAdrWidget.SetText then
            auxAdrWidget = buildDotWidget("adr", 0.356, 0.161, 18)
        end
        if auxAdrWidget and auxAdrWidget.SetText then
            local adr = (tel and tel.adrenaline) or 0
            local ar, ag, ab, aa
            if adr < 20 then
                -- ghost
                ar, ag, ab, aa = 0.4, 0.5, 1.0, 0.15
            elseif adr < 60 then
                -- building -- blue to cyan
                local t = (adr - 20) / 40
                ar = 0.1 + t * 0.3; ag = 0.4 + t * 0.5; ab = 1.0; aa = 0.4 + t * 0.5
            else
                -- peak -- gold pulse
                local flash = math.sin(pulse * 4.0) * 0.15 + 0.85
                ar = 1.0 * flash; ag = 0.75 * flash; ab = 0.05; aa = 1.0
            end
            pcall(function()
                -- Lightning bolt stand-in
                auxAdrWidget:SetText("!")
                auxAdrWidget:SetTintColor(HDRColor.new({ Red=ar, Green=ag, Blue=ab, Alpha=aa }))
                auxAdrWidget:SetVisible(true)
            end)
        end

        -- ---- BRAKE HEAT indicator (caliper icon, orange at threshold) ----
        if not auxBrakeWidget or not auxBrakeWidget.SetText then
            auxBrakeWidget = buildDotWidget("brake", 0.370, 0.161, 18)
        end
        if auxBrakeWidget and auxBrakeWidget.SetText then
            local clutchTemp = (tel and tel.clutchTemp) or 20
            local br, bg, bb, ba
            if clutchTemp < 60 then
                -- ghost
                br, bg, bb, ba = 0.5, 0.5, 0.6, 0.15
            elseif clutchTemp < 85 then
                -- warming -- blue to yellow
                local t = (clutchTemp - 60) / 25
                br = 0.3 + t * 0.7; bg = 0.5 + t * 0.3; bb = 0.8 - t * 0.7; ba = 0.3 + t * 0.6
            else
                -- hot -- orange/red, flash at critical
                local flash = clutchTemp > 100 and (math.floor(pulse * 8) % 2 == 0) and 0.6 or 1.0
                br = 1.0 * flash; bg = 0.35 * flash; bb = 0.02; ba = 1.0
            end
            pcall(function()
                -- C shape = caliper stand-in
                auxBrakeWidget:SetText("C")
                auxBrakeWidget:SetTintColor(HDRColor.new({ Red=br, Green=bg, Blue=bb, Alpha=ba }))
                auxBrakeWidget:SetVisible(true)
            end)
        end
    end

    -- ============================================================
    -- CLUTCH BAR -- vertical pedal stroke indicator
    -- 8 segments: top=in (disengaged), bottom=out (engaged)
    -- Friction zone (ramp 0.15-0.65) glows amber
    -- Only shown when mt_require_clutch is true
    -- ============================================================
    if settings.mt_require_clutch then
        if auxClutchWidget and auxClutchWidget.SetText then
            local ramp = state.clutchEngagementRamp or 1.0
            local SEGS = 8
            -- How many segments are "engaged" (lit) from bottom up
            local litCount = math.floor(ramp * SEGS + 0.5)
            local inFriction = (ramp >= 0.15 and ramp <= 0.65)

            -- Build bar top-to-bottom: top = clutch in, bottom = clutch out
            -- Lit segment char: solid block. Dim segment: light shade.
            -- ASCII-safe: use | for lit, . for dim (digital font friendly)
            local bar = ""
            for seg = SEGS, 1, -1 do
                if seg <= litCount then
                    bar = bar .. "|"
                else
                    bar = bar .. "."
                end
                if seg > 1 then bar = bar .. "\n" end
            end

            local cr, cg, cb, ca
            if state.isStalled then
                -- Stalled: flash red
                local flash = math.floor((state.healthPulse or 0) * 8) % 2
                cr = 1.0; cg = flash == 0 and 0.0 or 0.3; cb = 0.0; ca = 1.0
            elseif inFriction then
                -- Friction zone: amber
                cr = 1.0; cg = 0.55; cb = 0.05; ca = 1.0
            elseif ramp < 0.15 then
                -- Fully in: dim blue-white
                cr = 0.4; cg = 0.5; cb = 0.8; ca = 0.6
            else
                -- Fully out (engaged): mode colour at low alpha
                if state.raceMode == 2 then
                    cr = 0.8; cg = 0.15; cb = 0.1
                elseif state.raceMode == 1 then
                    cr = 0.2; cg = 0.45; cb = 1.0
                else
                    cr = 0.25; cg = 0.75; cb = 0.3
                end
                ca = 0.5
            end

            pcall(function()
                auxClutchWidget:SetText(bar)
                auxClutchWidget:SetTintColor(HDRColor.new({ Red = cr, Green = cg, Blue = cb, Alpha = ca }))
                auxClutchWidget:SetVisible(true)
            end)
        end
    end
end

-- ============================================================================
-- AUDIO REWARD SYSTEM (Audioware)
-- ============================================================================
local audioPools = {
    failed_shift = {
        "mt_v10_fail_01", "mt_v10_fail_02", "mt_v10_fail_03", "mt_v10_fail_04", "mt_v10_fail_05",
        "mt_v10_fail_06", "mt_v10_fail_07", "mt_v10_fail_08", "mt_v10_fail_09", "mt_v10_fail_10",
        "mt_v10_fail_11", "mt_v10_fail_12", "mt_v10_fail_13", "mt_v10_fail_14", "mt_v10_fail_15",
        "mt_v10_fail_16", "mt_v10_fail_17", "mt_v10_fail_18", "mt_v10_fail_19", "mt_v10_fail_20"
    },
    small_reward = {
        "mt_v10_small_01", "mt_v10_small_02", "mt_v10_small_03", "mt_v10_small_04", "mt_v10_small_05",
        "mt_v10_small_06", "mt_v10_small_07", "mt_v10_small_08", "mt_v10_small_09", "mt_v10_small_10",
        "mt_v10_small_11", "mt_v10_small_12", "mt_v10_small_13", "mt_v10_small_14", "mt_v10_small_15"
    },
    level_10_reward = {
        "mt_v10_level10_01", "mt_v10_level10_02", "mt_v10_level10_03", "mt_v10_level10_04",
        "mt_v10_level10_05", "mt_v10_level10_06", "mt_v10_level10_07", "mt_v10_level10_08",
        "mt_v10_level10_09"
    },
    level_20_reward = {
        "mt_v10_level20_01", "mt_v10_level20_02", "mt_v10_level20_03", "mt_v10_level20_04",
        "mt_v10_level20_05", "mt_v10_level20_06", "mt_v10_level20_07"
    },
}

local audioLastMilestone = 0

local function playCategory(category)
    if not settings.mt_audio_rewards then return end
    local pool = audioPools[category]
    if not pool or #pool == 0 then return end
    local soundName = pool[math.random(1, #pool)]
    local vol = settings["mt_vol_" .. category] or 0.65
    local ok, audioSystem = pcall(function() return Game.GetAudioSystem() end)
    if ok and audioSystem then
        pcall(function() audioSystem:Play(CName.new(soundName), vol) end)
    else
        -- Vanilla fallback
        local fallbacks = {
            failed_shift    = "ono_v_pain_short",
            small_reward    = "ui_menu_map_pin_added",
            level_10_reward = "ui_hud_journal_new_quest",
            level_20_reward = "ui_hud_level_up",
        }
        local fb = fallbacks[category]
        if fb then
            local player = Game.GetPlayer()
            if player then pcall(function() player:PlaySound(StringToName(fb), nil) end) end
        end
    end
end

local function playShiftFail()
    playCategory("failed_shift")
end

local function resetAudioMilestone()
    audioLastMilestone = 0
end

-- ============================================================================
-- HUMANITY / STRESS TRACKER
-- ============================================================================
local humanity = 50.0
local humanityWidget = nil
local stressFlash = 0

local function changeHumanity(delta)
    if not settings.mt_humanity_enabled then return end
    local prev = humanity
    humanity = math.max(0, math.min(100, humanity + delta))
    if math.abs(humanity - prev) >= 2.0 then
        stressFlash = 0.5
    end
end

local function changeDFNerve(delta)
    pcall(function()
        local dfs = Game.GetScriptableSystemsContainer():Get("DarkFuture.Needs.DFNerveSystem")
        if dfs then
            dfs:ChangeNeedValue(delta)
        end
    end)
end

local function updateHumanityWidget()
    if not state.inVehicle or not state.isManualMode then
        if humanityWidget and humanityWidget.SetVisible then
            pcall(function() humanityWidget:SetVisible(false) end)
        end
        return
    end
    if not humanityWidget or not humanityWidget.SetText then
        local inkSys = Game.GetInkSystem()
        if inkSys then
            local hudLayer = inkSys:GetLayer(StringToName("inkHUDLayer"))
            local container = hudLayer and hudLayer:GetVirtualWindow()
            if container then
                local existing = container:GetWidget(StringToName("V10Humanity"))
                if existing then container:RemoveChild(existing) end
                local w = inkText.new()
                w:SetName(StringToName("V10Humanity"))
                w:SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily")
                w:SetFontSize(18)
                w:SetAnchor(inkEAnchor.BottomLeft)
                w:SetAnchorPoint(0.5, 0.5)
                w:Reparent(container, -1)
                pcall(function()
                    local _, h = GetDisplayResolution()
                    w:SetMargin(inkMargin.new({ left = (h or 1080) * 0.30, top = 0, right = 0, bottom = (h or 1080) * 0.195 }))
                end)
                humanityWidget = w
            end
        end
    end
    if humanityWidget and humanityWidget.SetText then
        local temp = 20.0
        if thermalV12 then
            pcall(function()
                local tel = thermalV12.getTelemetry()
                if tel then temp = tel.clutchTemp or 20 end
            end)
        end
        local pulse = state.healthPulse or 0
        local tr, tg, tb = 0.15, 0.35, 1.0
        if temp < 40 then
            tr, tg, tb = 0.15, 0.35, 1.0
        elseif temp < 65 then
            local t = (temp - 40) / 25
            tr = 0.15 + t * 0.85; tg = 0.35 + t * 0.65; tb = 1.0 - t * 0.95
        elseif temp < 80 then
            local t = (temp - 65) / 15
            tr = 1.0; tg = 1.0 - t * 0.5; tb = 0.05
        elseif temp < 95 then
            local t = (temp - 80) / 15
            tr = 1.0; tg = 0.5 - t * 0.4; tb = 0.05
        elseif temp < 100 then
            tr, tg, tb = 1.0, 0.05, 0.05
        elseif temp < 112 then
            local flash = math.floor(pulse * 8) % 2
            tr = 1.0; tg = flash == 0 and 0.05 or 1.0; tb = flash == 0 and 0.05 or 1.0
        else
            local flash = math.floor(pulse * 12) % 2
            tr = 1.0; tg = flash == 0 and 0.05 or 0.75; tb = flash == 0 and 0.05 or 0.75
        end
        if (stressFlash or 0) > 0 then
            local blinkOn = math.floor(pulse * 10) % 2 == 0
            if blinkOn then tr, tg, tb = 1.0, 1.0, 1.0 end
        end
        pcall(function()
            humanityWidget:SetText(string.format("%.0f\194\176", temp))
            humanityWidget:SetTintColor(HDRColor.new({ Red = tr, Green = tg, Blue = tb, Alpha = 0.9 }))
            humanityWidget:SetVisible(settings.mt_humanity_enabled)
        end)
    end
end

-- ============================================================================
-- STREAK POPUP
-- ============================================================================
local popupWidget  = nil
local popupTimer   = 0
local popupMessage = ""
local popupStyle   = "normal"

local function showStreakPopup(msg, duration, style)
    popupMessage = msg
    popupTimer   = duration or 2.5
    popupStyle   = style or "normal"
end

-- playShiftReward defined here -- AFTER showStreakPopup so the call resolves
local function playShiftReward(streak)
    local milestone = 0
    if streak > 0 and streak % 10 == 0 then
        milestone = 10
    elseif streak >= settings.mt_reward_interval
       and streak % settings.mt_reward_interval == 0 then
        milestone = 2
    end
    if milestone == 0 or milestone == audioLastMilestone then return end
    audioLastMilestone = milestone
    if milestone == 10 then
        local isX20 = (math.floor(streak / 10) % 2 == 0)
        playCategory(isX20 and "level_20_reward" or "level_10_reward")
        local style = isX20 and "check20" or "check10"
        showStreakPopup("* x" .. streak .. " *", 3.0, style)
        if introSeq then
            if isX20 then
                pcall(function() introSeq.onStreak20() end)
            else
                pcall(function() introSeq.onStreak10() end)
                if voiceSystem then
                    pcall(function() voiceSystem.onFirstStreak10() end)
                end
            end
        end
        print("[V12 Racer] STREAK x" .. streak)
    else
        playCategory("small_reward")
    end
end

local function updatePopupWidget(dt)
    if popupTimer > 0 then
        popupTimer = popupTimer - dt
        if not popupWidget or not popupWidget.SetText then
            local inkSys = Game.GetInkSystem()
            if inkSys then
                local hudLayer = inkSys:GetLayer(StringToName("inkHUDLayer"))
                local container = hudLayer and hudLayer:GetVirtualWindow()
                if container then
                    local existing = container:GetWidget(StringToName("V10StreakPopup"))
                    if existing then container:RemoveChild(existing) end
                    local w = inkText.new()
                    w:SetName(StringToName("V10StreakPopup"))
                    w:SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily")
                    w:SetFontSize(55)
                    w:SetAnchor(inkEAnchor.TopCenter)
                    w:SetAnchorPoint(0.5, 0.0)
                    w:Reparent(container, -1)
                    pcall(function()
                        local _, h = GetDisplayResolution()
                        w:SetMargin(inkMargin.new({ left = 0, top = (h or 1080) * 0.10, right = 0, bottom = 0 }))
                    end)
                    popupWidget = w
                end
            end
        end
        if popupWidget and popupWidget.SetText then
            local alpha = math.min(1.0, popupTimer)
            local r, g, b
            if popupStyle == "check10" or popupStyle == "check20" then
                -- Waving checkered flag optical illusion
                -- Sine wave phase-shifted per character position
                -- creates rolling wave across the banner
                local waveSpeed  = popupStyle == "check20" and 6.0 or 4.0
                local waveTime   = (3.0 - popupTimer)  -- counts up as timer counts down
                local flashRate  = popupStyle == "check20" and 12.0 or 8.0
                local flash      = math.floor(popupTimer * flashRate) % 2

                -- Wave offset: sin wave rolled across horizontal position
                -- We approximate position via time offset on the flash cycle
                local waveOffset = math.sin(waveTime * waveSpeed) * 0.5 + 0.5
                local waveFlash  = math.floor((popupTimer * flashRate) + waveOffset * 2) % 2

                if popupStyle == "check10" then
                    -- Black and white checkered wave
                    if waveFlash == 0 then
                        r, g, b = 1.0, 1.0, 1.0   -- white
                    else
                        r, g, b = 0.04, 0.04, 0.04 -- black
                    end
                else
                    -- Gold and black checkered wave
                    if waveFlash == 0 then
                        r, g, b = 1.0, 0.82, 0.08  -- gold
                    else
                        r, g, b = 0.04, 0.04, 0.04  -- black
                    end
                end
            else
                local pulse = 0.85 + math.abs(math.sin(popupTimer * 4)) * 0.15
                r, g, b = 1.0 * pulse, 0.82 * pulse, 0.15 * pulse
            end
            pcall(function()
                popupWidget:SetText(popupMessage)
                popupWidget:SetTintColor(HDRColor.new({ Red = r, Green = g, Blue = b, Alpha = alpha }))
                popupWidget:SetVisible(true)
            end)
        end
    elseif popupWidget and popupWidget.SetVisible then
        pcall(function() popupWidget:SetVisible(false) end)
    end
end

-- ============================================================================
-- GEAR UI
-- ============================================================================
local function UpdateGearUI(selfController)
    if not state.inVehicle then return end

    local displayGear = state.displayGear or state.currentGear
    local isBike = state.playerVehicle and state.playerVehicle:IsA(CName("vehicleBikeBaseObject"))
    if isBike and displayGear == 0 then displayGear = -1 end

    local isClutchActive = (state.clutchMode == "disengaged")
        or state.persistentNeutralUI
        or (settings.mt_require_clutch and (state.digitalHold or state.analogWantsNeutral))

    if isClutchActive or displayGear == -1 then
        displayGear = "N"
    elseif displayGear == 0 then
        displayGear = "R"
    end

    local kick = state.kickFlash or 0
    if kick > 0 then
        if (state.healthPulse * 10) % 2 < 1 then displayGear = "!" end
    end

    local r, g, b = 0.35, 0.90, 0.40  -- Green

    if state.raceMode == 1 then
        r, g, b = 0.25, 0.55, 1.0     -- Blue
    elseif state.raceMode == 2 then
        local s = state.raceStreak or 0
        if     s <  5  then r, g, b = 0.55, 0.25, 0.28   -- dark red
        elseif s < 10  then r, g, b = 0.85, 0.18, 0.15   -- mid red
        elseif s < 20  then r, g, b = 1.0,  0.12, 0.08   -- hot red
        else                r, g, b = 1.0,  0.75, 0.15   end  -- gold at 20+
    end

    local occ = state.rpmOccupancy or 0
    if state.raceMode == 0 then
        local glow = 1.0 + occ * 0.4
        r, g, b = r * glow, g * glow, b * glow
    elseif state.raceMode == 1 then
        local dim = 1.0 - occ * 0.55
        r, g, b = r * dim, g * dim, b * dim
    end

    if kick > 0 then
        local osc = math.abs(math.sin(state.healthPulse * 28.0))
        r = 0.4 + osc * 1.8; g = osc * 0.15; b = osc * 0.05
    elseif (state.goodFlash or 0) > 0 and state.raceMode == 2 and (state.raceStreak or 0) >= 10 then
        r, g, b = 1.0, 0.82, 0.15
    elseif (state.rejectFlash or 0) > 0 then
        r, g, b = 0.35, 0.40, 0.12
    end

    local gearWidget = utils.getOrCreateGearWidget(
        displayGear, state.isManualMode, state.isFPP,
        settings.mt_show_fpp, settings.mt_show_tpp)

    if gearWidget and gearWidget.SetTintColor then
        pcall(function()
            gearWidget:SetTintColor(HDRColor.new({ Red = r, Green = g, Blue = b, Alpha = 1.0 }))
        end)
    end

    if selfController and gearWidget and not state.isFPP then
        local root = selfController:GetRootWidget()
        if root and root.parentWidget then
            utils.updateGearWidgetMargin(gearWidget)
            gearWidget:SetScale(root.parentWidget:GetScale())
        end
    end

    updateAuxWidgets()
    updateGhostGears(state.currentGear, state.raceMode, state.isFPP, settings.mt_show_fpp, settings.mt_show_tpp)
    return gearWidget
end

-- ============================================================================
-- VEHICLE STATE MANAGEMENT
-- ============================================================================
local function SetupVehicleState(vehicle)
    state.playerVehicle     = vehicle
    state.inVehicle         = true
    state.vehicleBlackboard = vehicle:GetBlackboard()
    state.vehicleStats      = utils.getVehicleGearData()
    state.entryGrace        = 2.0
    state.raceMode      = 1       -- default Blue on every entry (closest to vanilla)
    state.raceStreak    = 0
    state.rejectFlash   = 0
    state.goodFlash     = 0
    state.kickFlash     = 0
    state.blueAutoArmed  = true
    state.blueIntentHigh = false
    state.blueIntentLow  = false
    state.rpmOccupancy   = 0
    state.blinkerLeft   = false
    state.blinkerRight  = false
    state.blinkerHazard = false
    state.smBrakeHold = 0
    if ShiftModes then pcall(function() ShiftModes.onVehicle(state) end) end
    if thermalV12   then pcall(function() thermalV12.init()   end) end
    if introSeq     then pcall(function() introSeq.init()     end) end
    if voiceSystem  then pcall(function() voiceSystem.init()  end) end

    -- Bikes: sequential only -- force Green on entry
    local isBikeEntry = pcall(function()
        if vehicle:IsA(CName("vehicleBikeBaseObject")) then
            state.raceMode = 0
        end
    end)

    if settings.mt_per_vehicle_memory then
        local vehicleKey = getVehicleKey(vehicle)
        state.currentVehicleKey = vehicleKey
        if vehicleKey and vehicleModes[vehicleKey] ~= nil then
            state.isManualMode = vehicleModes[vehicleKey]
        else
            state.isManualMode = settings.isManualMode
        end
    else
        state.isManualMode = settings.isManualMode
    end
end

local function ResetVehicleState()
    if state.isLocked then GameOptions.Toggle("Vehicle", "BlockChangeGear", "false") end
    pcall(function() Game.MtSetThrottle(1.0)  end)
    pcall(function() Game.MtClutchEngage()    end)
    state.inVehicle         = false
    state.playerVehicle     = nil
    state.vehicleStats      = nil
    state.vehicleBlackboard = nil
    state.isManualMode      = false
    state.shifting          = false
    state.isLocked          = false
    state.entryGrace        = 0
    state.clutchAmount      = 0.0
    state.clutchMode        = "engaged"
    state.lastClutchMode    = "engaged"
    state.clutchHoldTimer   = 0.0
    state.persistentNeutralUI = false
    state.digitalHold       = false
    state.analogWantsNeutral= false
    state.lastValidGear     = nil
    state.currentVehicleKey = nil
    state.ghostGear         = nil
    state.kbNeutralLocked   = false   -- latch must not survive a vehicle change
    state.isFakeBraking     = false
    state.confirmTimer      = 0       -- stuck confirmTimer deadlocks Green keyboard shifts
    state.pendingGear       = nil
    state.displayGear       = nil
    state.blinkerLeft       = false
    state.blinkerRight      = false
    state.blinkerHazard     = false
    auxRPMWidget    = nil
    auxHeatWidget   = nil
    auxClutchWidget = nil
    auxStressWidget = nil
    auxAdrWidget    = nil
    auxBrakeWidget  = nil
    auxInkSystem    = nil
end

local function ExecuteRecoveryShift(engageGear)
    if state.isLocked then Gearbox.SetLock(state, false) end
    state.currentGear  = engageGear
    state.targetGear   = nil
    state.shifting     = true
    state.shiftTimeout = 0.2
    Gearbox.ForceGameShift(state, state.playerVehicle, engageGear)
    pcall(function()
        Game.MtSetRecoveryGear(engageGear)
        Game.MtSetThrottle(1.0)
        Game.MtClutchEngage()
    end)
end

local function SyncVehicleState()
    if utils.forceUIReload then utils.forceUIReload() end
    utils.clearCache()
    utils.getOrCreateGearWidget(false, false, false, settings.mt_show_fpp, settings.mt_show_tpp)
    local player = Game.GetPlayer()
    if player and utils.isDriver() then
        local vehicle = Game.GetMountedVehicle(player)
        if vehicle then SetupVehicleState(vehicle) end
    else
        ResetVehicleState()
    end
end


-- ============================================================================
-- EVENTS
-- ============================================================================
registerForEvent("onInit", function()
    -- Menu registration. Wrapped so the two silent failure modes become visible:
    --   1. GetMod returns nil (nativeSettings not loaded yet) -> retried below
    --   2. an add* call throws -> printed, instead of aborting onInit unnoticed
    local function SetupNativeSettings()
        local nativeSettings = GetMod("nativeSettings")
        if not nativeSettings then return false end
        nativeSettings.addTab(settingsPath, "V12 RAPTOR DOUGLAS 911")

        nativeSettings.addSubcategory(settingsPath .. "/gameplay", "General Gameplay")
        nativeSettings.addSwitch(settingsPath .. "/gameplay", "Enable Mod", "Master switch.", settings.enabled, true, function(v) settings.enabled = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addSwitch(settingsPath .. "/gameplay", "Require Clutch to Shift", "Must disengage engine before shifting.", settings.mt_require_clutch, false, function(v) settings.mt_require_clutch = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addSwitch(settingsPath .. "/gameplay", "Per-Vehicle Memory", "Remember Manual/Auto per vehicle.", settings.mt_per_vehicle_memory, false, function(v) settings.mt_per_vehicle_memory = v; config.saveFile(CONFIG_PATH, settings) end)

        nativeSettings.addSubcategory(settingsPath .. "/visuals", "HUD & Visuals")
        nativeSettings.addSwitch(settingsPath .. "/visuals", "Show Gear UI in First-Person", "", settings.mt_show_fpp, true, function(v) settings.mt_show_fpp = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addSwitch(settingsPath .. "/visuals", "Show Gear UI in Third-Person", "", settings.mt_show_tpp, true, function(v) settings.mt_show_tpp = v; config.saveFile(CONFIG_PATH, settings) end)

        nativeSettings.addSubcategory(settingsPath .. "/racing", "V12 Racer Modes")
        nativeSettings.addSwitch(settingsPath .. "/racing", "Enable Racer Modes", "Adds Blue (Shiftronic) and Red (H-Pattern) alongside original Green (Sequential).", settings.mt_racing_enabled, true, function(v) settings.mt_racing_enabled = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/racing", "Cycle Mode (NumPad .)", "Cycles Green -> Blue -> Red -> Green.", settings.mt_racing_toggle_key, "IK_NumPeriod", false, function(v) settings.mt_racing_toggle_key = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addButton(settingsPath .. "/racing", "H-Gate Layout (Red)", "NumPad4=1st  NumPad1=2nd  NumPad5=3rd  NumPad2=4th  NumPad6=5th  NumPad3=6th  NumPad0=Neutral  NumPad7=Reverse", "Fixed", 45, function() end)
        nativeSettings.addKeyBinding(settingsPath .. "/racing", "Reverse Gate (Red)", "From Neutral only, clutch held, near standstill.", settings.mt_gear_reverse_key, "IK_NumPad7", false, function(v) settings.mt_gear_reverse_key = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addRangeInt(settingsPath .. "/racing", "Small Reward Every N Shifts", "How many consecutive good shifts trigger the small audio reward.", 1, 10, 1, settings.mt_reward_interval, 2, function(v) settings.mt_reward_interval = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addSwitch(settingsPath .. "/racing", "Audio Rewards", "Enable shift reward and fail audio.", settings.mt_audio_rewards, true, function(v) settings.mt_audio_rewards = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addSwitch(settingsPath .. "/racing", "Humanity Tracker", "Show temp on HUD.", settings.mt_humanity_enabled, false, function(v) settings.mt_humanity_enabled = v; config.saveFile(CONFIG_PATH, settings) end)

        nativeSettings.addSubcategory(settingsPath .. "/audio_vol", "Audio Volumes")
        nativeSettings.addRangeFloat(settingsPath .. "/audio_vol", "Fail Sounds",         "Bad shift volume.",          0.0, 1.5, 0.05, "%.2f", settings.mt_vol_failed_shift,    0.65, function(v) settings.mt_vol_failed_shift    = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addRangeFloat(settingsPath .. "/audio_vol", "Small Rewards",        "Every-N-shift volume.",      0.0, 1.5, 0.05, "%.2f", settings.mt_vol_small_reward,    0.65, function(v) settings.mt_vol_small_reward    = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addRangeFloat(settingsPath .. "/audio_vol", "Medium Rewards (x10)", "Streak-10 volume.",          0.0, 1.5, 0.05, "%.2f", settings.mt_vol_level_10_reward, 0.65, function(v) settings.mt_vol_level_10_reward = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addRangeFloat(settingsPath .. "/audio_vol", "Large Rewards (x20)",  "Streak-20 volume.",          0.0, 1.5, 0.05, "%.2f", settings.mt_vol_level_20_reward, 0.65, function(v) settings.mt_vol_level_20_reward = v; config.saveFile(CONFIG_PATH, settings) end)

        nativeSettings.addSubcategory(settingsPath .. "/blinkers", "Turn Signals")
        nativeSettings.addSwitch(settingsPath .. "/blinkers", "Enable Blinkers", "Left/Right arrow keys toggle turn signals.", settings.mt_blinkers_enabled, true, function(v) settings.mt_blinkers_enabled = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/blinkers", "Left Signal",  "", settings.mt_blinker_left_key,  "IK_Left",  false, function(v) settings.mt_blinker_left_key  = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/blinkers", "Right Signal", "", settings.mt_blinker_right_key, "IK_Right", false, function(v) settings.mt_blinker_right_key = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/blinkers", "Hazard Lights","", settings.mt_blinker_hazard_key,"IK_H",     false, function(v) settings.mt_blinker_hazard_key = v; config.saveFile(CONFIG_PATH, settings) end)

        nativeSettings.addSubcategory(settingsPath .. "/binds_pad", "Gamepad / Controller")
        nativeSettings.addSwitch(settingsPath .. "/binds_pad", "Ignore Gamepad Inputs", "For sim-rig users.", settings.mt_ignore_pad, false, function(v) settings.mt_ignore_pad = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addButton(settingsPath .. "/binds_pad", "Clutch: Pull Left Stick Down", "Simulates a physical clutch pedal.", "Locked", 45, function() end)
        nativeSettings.addButton(settingsPath .. "/binds_pad", "Upshift: Tap A / Cross", "", "Locked", 45, function() end)
        nativeSettings.addButton(settingsPath .. "/binds_pad", "Downshift: Tap X / Square", "", "Locked", 45, function() end)
        nativeSettings.addButton(settingsPath .. "/binds_pad", "Neutral: Hold X / Square", "", "Locked", 45, function() end)
        nativeSettings.addButton(settingsPath .. "/binds_pad", "Toggle Mod: Hold X + Tap A", "", "Locked", 45, function() end)
        nativeSettings.addButton(settingsPath .. "/binds_pad", "Handbrake / Exit: B / Circle", "", "Locked", 45, function() end)

        nativeSettings.addSubcategory(settingsPath .. "/binds_kb", "Keyboard & Mapping Software")
        nativeSettings.addSwitch(settingsPath .. "/binds_kb", "Mouse Wheel Shifting", "", settings.mt_use_mouse_wheel, false, function(v) settings.mt_use_mouse_wheel = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/binds_kb", "Upshift",            "", settings.mt_upshift_key,   "IK_Up",       false, function(v) settings.mt_upshift_key    = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/binds_kb", "Downshift",          "", settings.mt_downshift_key, "IK_Down",     false, function(v) settings.mt_downshift_key  = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/binds_kb", "Clutch Pedal",       "", settings.mt_clutch_key,   "IK_LControl", false, function(v) settings.mt_clutch_key     = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/binds_kb", "Toggle Manual Mode", "", settings.mt_toggle_key,   "IK_M",        false, function(v) settings.mt_toggle_key     = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addKeyBinding(settingsPath .. "/binds_kb", "Toggle Neutral",     "", settings.mt_neutral_key,  "IK_G",        false, function(v) settings.mt_neutral_key    = v; config.saveFile(CONFIG_PATH, settings) end)

        nativeSettings.addSubcategory(settingsPath .. "/clutch", "Advanced Drivetrain Tuning")
        nativeSettings.addRangeFloat(settingsPath .. "/clutch", "Slip Threshold",     "", 0.0, 1.0, 0.01, "%.2f", settings.mt_clutch_slip_enter,    0.15, function(v) settings.mt_clutch_slip_enter    = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addRangeFloat(settingsPath .. "/clutch", "Neutral Threshold",  "", 0.0, 1.0, 0.01, "%.2f", settings.mt_clutch_neutral_enter,  0.80, function(v) settings.mt_clutch_neutral_enter  = v; config.saveFile(CONFIG_PATH, settings) end)
        nativeSettings.addRangeFloat(settingsPath .. "/clutch", "Re-engage Threshold","", 0.0, 1.0, 0.01, "%.2f", settings.mt_clutch_reengage_exit,  0.65, function(v) settings.mt_clutch_reengage_exit  = v; config.saveFile(CONFIG_PATH, settings) end)
        print("[V12 RD911] NativeSettings registered.")
        return true
    end


    eng = GetMod("0-Engine")
    if not eng then
        print("[V12 Racer] FATAL: 0-Engine not found. Mod will not load.")
        return
    end
    eng.Register("ManualTransmissionV12")
    print("[V12 Racer] Registered with 0-Engine " .. tostring(eng.GetVersion()))

    -- Menu: attempt now, retry every 0.5s for 10s if nativeSettings isn't up yet.
    -- FIX 2026-08-04 (C): menu failures were print()-only. print() goes to the
    -- CET console, which is not scrollable here and is NOT written to the mod
    -- .log file -- so every menu failure so far has been invisible to everyone.
    -- Mirror it to menu_debug.txt in the mod folder so it can actually be read.
    local function menuLog(line)
        pcall(function()
            local f = io.open("menu_debug.txt", "a")
            if f then
                f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. tostring(line) .. "\n")
                f:close()
            end
        end)
        print("[V12 RD911] " .. tostring(line))
    end

    menuLog("---- menu boot attempt ----")

    local menuTries = 0
    local function tryMenu()
        menuTries = menuTries + 1
        local ok, res = pcall(SetupNativeSettings)
        if not ok then
            menuLog("MENU ERROR (try " .. menuTries .. ") >>> " .. tostring(res))
            return
        end
        if res then
            menuLog("MENU OK on try " .. menuTries .. " -- tab registered as V12 RAPTOR DOUGLAS 911")
            return
        end
        if menuTries < 20 then
            if menuTries == 1 then menuLog("GetMod(nativeSettings) returned nil, retrying") end
            eng.SetTimeout(0.5, tryMenu)
        else
            menuLog("MENU FAIL: nativeSettings never appeared after 10s / 20 tries.")
        end
    end
    tryMenu()


    -- ---- Boot sequence ----
    local function bootLine(t, text)
        eng.SetTimeout(t, function() print(text) end)
    end
    local bv = tostring(eng.GetVersion())
    bootLine(0.00, "[V12 RD911] ============================================")
    bootLine(0.10, "[V12 RD911] RAPTOR DOUGLAS 911  //  V12 SYSTEMS ONLINE")
    bootLine(0.20, "[V12 RD911] ============================================")
    bootLine(0.35, "[V12 RD911] 0-Engine " .. bv .. " ................. [OK]")
    bootLine(0.50, "[V12 RD911] Gearbox Module ..................... [OK]")
    bootLine(0.65, "[V12 RD911] Thermal Framework .................. [OK]")
    bootLine(0.80, "[V12 RD911] Stress / Nerves .................... [OK]")
    bootLine(0.95, "[V12 RD911] Adrenaline System .................. [OK]")
    bootLine(1.10, "[V12 RD911] Clutch Heat Monitor ................ [OK]")
    bootLine(1.25, "[V12 RD911] Weather Integration ................ [OK]")
    bootLine(1.40, "[V12 RD911] Survival Run Tracker ............... [OK]")
    bootLine(1.55, "[V12 RD911] DUI Record System .................. [OK]")
    bootLine(1.70, "[V12 RD911] Voice System ....................... [OK]")
    bootLine(1.85, "[V12 RD911] Initiation Sequence ................ [OK]")
    bootLine(2.00, "[V12 RD911] Ghost in the Machine ............... [ARMED]")
    bootLine(2.20, "[V12 RD911] ============================================")
    bootLine(2.40, "[V12 RD911] ALL SYSTEMS NOMINAL.")
    bootLine(2.55, "[V12 RD911] DRIVE FAST. SHIFT CLEAN. STAY HUMAN.")
    bootLine(2.70, "[V12 RD911] ============================================")

    eng.WhenReady(function()
    local allDefs  = Game.GetAllBlackboardDefs()
    bbVehicleDef   = allDefs.Vehicle
    Gearbox.initialize()
    if inputManager.onHook then inputManager.onHook() end

    GameUI.Observe(GameUI.Event.SessionStart, function() SyncVehicleState() end)

    GameUI.Observe(GameUI.Event.VehicleEnter, function()
        local player = Game.GetPlayer()
        if player and utils.isDriver() then
            local vehicle = Game.GetMountedVehicle(player)
            if vehicle then SetupVehicleState(vehicle) end
        end
    end)

    GameUI.Observe(GameUI.Event.VehicleExit, function()
        ResetVehicleState()
        utils.getOrCreateGearWidget(false, false, false, settings.mt_show_fpp, settings.mt_show_tpp)
    end)

    Observe("gameuiCrosshairContainerController", "OnPSMVehicleInTPPChanged", function(self, isTPP)
        state.isFPP = not isTPP
        UpdateGearUI(self)
    end)

    Observe("gameuiCrosshairContainerController", "OnPreIntro", function(self)
        UpdateGearUI(self)
    end)

    -- ---- Death audio trigger ----
    -- Fires a random failed_shift sound on player death.
    -- If it starts before the death screen fades in, it plays through it.
    Observe("PlayerPuppet", "OnDeath", function(self)
        if not settings.mt_audio_rewards then return end
        local pool = audioPools.failed_shift
        if not pool or #pool == 0 then return end
        local soundName = pool[math.random(1, #pool)]
        -- heart.ogg is in the pool -- good chance it fires here
        local vol = settings.mt_vol_failed_shift or 0.65
        local ok, audioSystem = pcall(function() return Game.GetAudioSystem() end)
        if ok and audioSystem then
            pcall(function() audioSystem:Play(CName.new(soundName), vol) end)
        end
        print("[V12 Racer] Death trigger fired: " .. soundName)
    end)

    Override("VehicleComponent", "OnAction", function(self, action, consumer, wrappedMethod)
        local actionName  = ListenerAction.GetName(action)
        local actionValue = ListenerAction.GetValue(action)

        if inputManager.onAction then
            inputManager.onAction(action, consumer)
        end

        if ListenerAction.IsAction(action, "VehicleHandbrake") then
            if ListenerAction.IsButtonJustPressed(action)  then state.isHandbraking = true  end
            if ListenerAction.IsButtonJustReleased(action) then state.isHandbraking = false end
        end
        if ListenerAction.IsAction(action, "VehicleHorn") then
            if ListenerAction.IsButtonJustPressed(action)  then state.isHonking = true  end
            if ListenerAction.IsButtonJustReleased(action) then state.isHonking = false end
        end
        if ListenerAction.IsAction(action, "UseConsumable") and state.isHonking then
            ListenerActionConsumer.Consume(consumer)
        end
        local isBike = state.playerVehicle and state.playerVehicle:IsA(CName("vehicleBikeBaseObject"))
        if isBike and settings.mt_require_clutch then
            if ListenerAction.IsAction(action, "left_stick_y")
            or ListenerAction.IsAction(action, "MoveY") then
                local axisKey = settings.mt_clutch_axis or "IK_Pad_LeftAxisY"
                local axisRaw = (axisKey ~= "" and inputManager.axisValues and inputManager.axisValues[axisKey]) or 0
                if math.max(0, -axisRaw) >= 0.95 then
                    ListenerActionConsumer.Consume(consumer)
                end
            end
        end
        if ListenerAction.IsAction(action, "Exit") and state.isHandbraking then
            local isSk = state.playerVehicle and state.playerVehicle:IsSkidding(0.3) or false
            if state.isAccelerating or isSk then
                ListenerActionConsumer.Consume(consumer)
            end
        end
        if ListenerAction.IsAction(action, "Accelerate") then
            local res = HandlePedalAction(action, actionValue)
            if res ~= nil then state.isAccelerating = res end
        end
        if ListenerAction.IsAction(action, "Decelerate") then
            local res = HandlePedalAction(action, actionValue)
            if res ~= nil then state.isDecelerating = res end
        end
        return wrappedMethod(action, consumer)
    end)


    SyncVehicleState()
    end) -- eng.WhenReady
end)

registerForEvent("onOverlayOpen", function()
    SyncVehicleState()
end)

registerForEvent("onShutdown", function()
    if state.isLocked then GameOptions.Toggle("Vehicle", "BlockChangeGear", "false") end
    pcall(function() Game.MtSetThrottle(1.0) end)
    pcall(function() Game.MtClutchEngage()   end)
    if inputManager and inputManager.onShutdown then inputManager.onShutdown() end
    utils.getOrCreateGearWidget(false, false, false, settings.mt_show_fpp, settings.mt_show_tpp)
    utils.clearCache()
end)

-- ============================================================================
-- ON UPDATE
-- ============================================================================
registerForEvent("onUpdate", function(dt)
    inputManager.onUpdate(dt)
    -- Cron.Update removed: 0-Engine manages timing internally

    if not state.inVehicle
    or not state.playerVehicle
    or not state.vehicleBlackboard
    or not state.playerVehicle:IsAttached() then return
    end

    -- FIX 2026-08-04 (A): late-resolve the Vehicle blackboard def.
    -- eng.WhenReady (line 1174) can fire before the blackboard system is
    -- populated, so line 1176 stored nil. Assigning nil does not throw, so it
    -- failed silently and every frame below died indexing it -- which killed
    -- gear reads, shifting, reverse, the F-key mode cycle and the UI refresh.
    -- Retry here until it resolves. If it never does, we return quietly
    -- instead of throwing 60 times a second.
    if not bbVehicleDef then
        local okDefs, defs = pcall(Game.GetAllBlackboardDefs)
        if okDefs and defs then bbVehicleDef = defs.Vehicle end
        if not bbVehicleDef then return end
        print("[V12 RD911] Vehicle blackboard def resolved late -- update loop live.")
    end

    local isBike     = state.playerVehicle:IsA(CName("vehicleBikeBaseObject"))
    local isSkidding = state.playerVehicle:IsSkidding(0.5)

    state.currentGear = state.vehicleBlackboard:GetInt(bbVehicleDef.GearValue)
    state.speed       = state.vehicleBlackboard:GetFloat(bbVehicleDef.SpeedValue)
    if state.currentGear > 0 then state.lastValidGear = state.currentGear end
    if state.entryGrace > 0  then state.entryGrace = state.entryGrace - dt end

    -- Gear confirm: show requested gear for up to 0.3s, revert if not confirmed
    if (state.confirmTimer or 0) > 0 then
        state.confirmTimer = state.confirmTimer - dt
        if state.currentGear == state.pendingGear then
            -- Blackboard agrees -- confirmed
            state.displayGear  = state.currentGear
            state.confirmTimer = 0
            state.goodFlash    = 0.25
        elseif state.confirmTimer <= 0 then
            -- Timed out -- revert display, show reject flash
            state.displayGear  = state.currentGear  -- show whatever game landed on
            state.rejectFlash  = 0.25
        end
    else
        state.displayGear = state.currentGear
    end

    if not inputManager.axisValues then inputManager.axisValues = {} end

    -- ---- Pulse + timer decays ----
    state.healthPulse  = (state.healthPulse or 0) + dt
    updatePopupWidget(dt)
    updateHumanityWidget()
    if (state.kickFlash   or 0) > 0 then state.kickFlash   = state.kickFlash   - dt end
    if (state.goodFlash   or 0) > 0 then state.goodFlash   = state.goodFlash   - dt end
    if (state.rejectFlash or 0) > 0 then state.rejectFlash = state.rejectFlash - dt end
    if (stressFlash       or 0) > 0 then stressFlash       = stressFlash       - dt end

    -- Shift watchdog: if state.shifting stuck for > 1.5s, force-unlock
    if state.shifting then
        state.shiftWatchdog = (state.shiftWatchdog or 0) + dt
        if state.shiftWatchdog > 1.5 then
            state.shifting      = false
            state.shiftWatchdog = 0
            pcall(function() Gearbox.SetLock(state, true) end)
            print("[V12 RD911] Shift watchdog fired -- shift state force-reset")
        end
    else
        state.shiftWatchdog = 0
    end

    -- ---- Blinkers ----
    updateBlinkers(dt)

    -- ---- RPM occupancy ----
    state.rpmOccupancy = 0
    if state.vehicleStats and state.vehicleStats.gears then
        local gd = state.vehicleStats.gears[state.currentGear]
        if gd and gd.minSpeed and gd.maxSpeed and gd.maxSpeed > gd.minSpeed then
            local occ = (math.abs(state.speed) - gd.minSpeed) / (gd.maxSpeed - gd.minSpeed)
            state.rpmOccupancy = math.max(0, math.min(1, occ))
        end
    end

    -- ---- Voice system update ----
    if voiceSystem then
        pcall(function()
            local wantedLevel = 0
            -- Read DF Nerve -- confirmed working: returns 0-100
            local dfNerve = 100.0
            pcall(function()
                local dfs = Game.GetScriptableSystemsContainer():Get("DarkFuture.Needs.DFNerveSystem")
                if dfs then dfNerve = dfs:GetNeedValue() or 100.0 end
            end)
            local tel = thermalV12 and thermalV12.getTelemetry() or nil
            voiceSystem.update(dt, {
                isInVehicle  = state.inVehicle,
                isRedMode    = (state.raceMode == 2),
                speed        = state.speed,
                steerInput   = 0,
                wantedLevel  = wantedLevel,
                drunkLevel   = (tel and tel.isDrunk) and 0.6 or 0.0,
                dfNerve      = dfNerve,
            })
        end)
    end
    -- ---- Intro sequence update ----
    if introSeq then
        pcall(function() introSeq.update(dt) end)
        pcall(function() introSeq.updateStreak(dt) end)
    end
    if thermalV12 then
        local isClutchSlipping = (state.clutchMode ~= "engaged")
                              and (state.rpmOccupancy > 0.4)
                              and (math.abs(state.speed) < 12.0)
        local rpmProxy  = 1500 + state.rpmOccupancy * 5000
        local topSpeed  = (state.vehicleStats and state.vehicleStats.topSpeed) or 0
        pcall(function()
            thermalV12.update(
                dt,
                state.speed,
                state.inVehicle,
                isClutchSlipping,
                rpmProxy,
                topSpeed,
                state.raceMode
            )
        end)
    end

    -- ---- Inputs ----
    local kbToggleHit   = checkInput(settings.mt_toggle_key)
    local kbNeutralHit  = checkInput(settings.mt_neutral_key)
    local kbUpshiftHit, kbDownshiftHit = false, false

    if settings.mt_use_mouse_wheel then
        kbUpshiftHit   = state.mouseWheelUpshift
        kbDownshiftHit = state.mouseWheelDownshift
        checkInput(settings.mt_upshift_key)
        checkInput(settings.mt_downshift_key)
    else
        kbUpshiftHit   = checkInput(settings.mt_upshift_key)
        kbDownshiftHit = checkInput(settings.mt_downshift_key)
    end
    state.mouseWheelUpshift   = false
    state.mouseWheelDownshift = false

    local padDownshiftPressed, padDownshiftTapped = checkTap(settings.mt_downshift_pad, dt, 0.4)
    local padDownshiftHit = isBike and padDownshiftPressed or padDownshiftTapped

    local padUpshiftPressed, _ = checkTap(settings.mt_upshift_pad, dt, 0.3)
    local padUpshiftHit = padUpshiftPressed
    if isHoldingInput(settings.mt_downshift_pad) and padUpshiftPressed then
        state.keyHoldTimes[settings.mt_upshift_pad] = 999
    end
    if settings.mt_ignore_pad then padUpshiftHit = false; padDownshiftHit = false end

    local isActualNeutral = (state.currentGear == -1) or (isBike and state.currentGear == 0) or state.persistentNeutralUI
    if isActualNeutral then
        if state.isAccelerating  then kbDownshiftHit = false; padDownshiftHit = false end
        if state.isDecelerating  then kbUpshiftHit   = false; padUpshiftHit   = false end
    end

    local shiftHit    = kbUpshiftHit or kbDownshiftHit or padUpshiftHit or padDownshiftHit
    local reqClutch   = settings.mt_require_clutch
    local axisKey     = settings.mt_clutch_axis or ""
    local axisRaw     = (axisKey ~= "" and inputManager.axisValues and inputManager.axisValues[axisKey]) or 0
    local axisClutch  = math.max(0, -axisRaw)
    local analogClutchPressed = (axisClutch >= settings.mt_clutch_slip_enter)
    local kbClutchPressed     = isHoldingInput(settings.mt_clutch_key)
    local wasInPersistentNeutral = state.persistentNeutralUI
    local isClutchPedalHeld   = kbClutchPressed or analogClutchPressed
    local clutchSatisfied     = not reqClutch or isClutchPedalHeld
    local validShiftHit       = shiftHit and clutchSatisfied

    -- ---- Shift timeout ----
    if state.shifting then
        state.shiftTimeout = state.shiftTimeout - dt
        if state.shiftTimeout <= 0 then
            state.shifting = false
            if isBike and state.targetGear == 1 and state.currentGear == 0 then
                Gearbox.ForceGameShift(state, state.playerVehicle, 1)
                state.currentGear = 1
            elseif state.clutchMode ~= "disengaged" then
                state.targetGear = state.currentGear
            end
            Gearbox.SetLock(state, true)
        end
    end

    if settings.enabled and not state.shifting then
        -- ---- Toggle manual mode ----
        local toggledThisFrame = false
        local toggleTriggered  = kbToggleHit or (padUpshiftHit and isHoldingInput(settings.mt_downshift_pad))

        if toggleTriggered then
            state.isManualMode = not state.isManualMode
            Gearbox.SetLock(state, false)
            Gearbox.ForceGameShift(state, state.playerVehicle, -1)
            toggledThisFrame = true
            if settings.mt_per_vehicle_memory then
                if state.currentVehicleKey then
                    vehicleModes[state.currentVehicleKey] = state.isManualMode
                    saveVehicleModes()
                end
            else
                settings.isManualMode = state.isManualMode
                config.saveFile(CONFIG_PATH, settings)
            end
            if not state.isManualMode then
                pcall(function() Game.MtSetThrottle(1.0) end)
                pcall(function() Game.MtClutchEngage()   end)
                state.clutchAmount       = 0.0
                state.clutchMode         = "engaged"
                state.lastClutchMode     = "engaged"
                state.clutchHoldTimer    = 0.0
                state.persistentNeutralUI= false
                state.digitalHold        = false
                state.analogWantsNeutral = false
                state.confirmTimer       = 0
                state.pendingGear        = nil
                state.displayGear        = nil
            end
            if padUpshiftHit   then padUpshiftHit   = false end
            if padDownshiftHit then padDownshiftHit  = false end
            state.keyHoldTimes[settings.mt_downshift_pad] = 999
        end

        -- ---- Cycle race mode ----
        if settings.mt_racing_enabled and checkInput(settings.mt_racing_toggle_key)
        and state.isManualMode then
            local isBikeForMode = state.playerVehicle and state.playerVehicle:IsA(CName("vehicleBikeBaseObject"))
            if isBikeForMode then
                -- Bikes are sequential only -- lock to Green, flash reject
                state.raceMode  = 0
                state.kickFlash = 0.3
                print("[V12 RD911] Bikes: Sequential only.")
            else
                state.raceMode       = (state.raceMode + 1) % 3
                state.blueAutoArmed  = true
                state.blueIntentHigh = false
                state.blueIntentLow  = false

                -- Clear the neutral latches when changing mode.
                -- Red sets kbNeutralLocked on its Neutral and bad-shift paths, but the
                -- ONLY code that clears it lives in Clutch.updateState, which V12 calls
                -- in Green's branch alone. Leave Red latched and Green's
                -- getEngagementLevel returns 0.0 -> throttle 0 -> no power, no shifting,
                -- permanently stuck in Neutral. The latch even survives vehicle swaps.
                state.kbNeutralLocked     = false
                state.persistentNeutralUI = false
                state.kickFlash      = 0
                state.goodFlash     = 0.35
                if not state.shifting then Gearbox.SetLock(state, true) end
                local names = { [0] = "Green  Sequential", [1] = "Blue  Shiftronic", [2] = "Red  H-Pattern" }
                print("[V12 RD911] Mode: " .. names[state.raceMode])
            end
            UpdateGearUI()
        end

        -- ---- Ctrl+Down = force Neutral (Green and Red) ----
        if state.isManualMode and state.raceMode ~= 1
        and isHoldingInput(settings.mt_clutch_key) and kbDownshiftHit then
            if not state.shifting then
                state.shifting            = true
                state.blueAutoArmed       = false
                state.kbNeutralLocked     = true
                state.persistentNeutralUI = true
                Gearbox.SetLock(state, false)
                Gearbox.ForceGameShift(state, state.playerVehicle, -1)
                state.currentGear = -1
                eng.SetTimeout(0.15, function()
                    if state.inVehicle then
                        pcall(function()
                            Game.MtSetRecoveryGear(-1)
                            Game.MtClutchDisengage()
                        end)
                        Gearbox.SetLock(state, true)
                        state.shifting = false
                    end
                end)
                kbDownshiftHit = false
            end
        end

        -- ==============================
        -- MODE DISPATCH
        -- ==============================
        if state.isManualMode and not toggledThisFrame then

            local clutchEngagement = 1.0

            -- ==========================
            -- GREEN  -  Original V10 behaviour, fully preserved
            -- ==========================
            if state.raceMode == 0 then
                if not state.shifting and not state.isLocked then
                    Gearbox.SetLock(state, true)
                end

                local safeKbNeutralHit = kbNeutralHit and clutchSatisfied
                local function safeIsHoldingInput(keyName)
                    if (keyName == settings.mt_downshift_pad or keyName == settings.mt_neutral_key)
                    and not clutchSatisfied then return false end
                    return isHoldingInput(keyName)
                end

                local postComboShiftHit = kbUpshiftHit or kbDownshiftHit or padUpshiftHit or padDownshiftHit
                local postComboValid = postComboShiftHit and clutchSatisfied
                Clutch.updateState(state, settings, inputManager, safeIsHoldingInput, safeKbNeutralHit, postComboValid, dt, isSkidding, isBike)
                clutchEngagement = Clutch.getEngagementLevel(state, settings)

                local isDPadHeld = isHoldingInput("IK_Pad_DigitLeft") or isHoldingInput("IK_Pad_DigitRight")
                    or isHoldingInput("IK_Pad_DigitDown") or isHoldingInput("IK_Pad_DigitUp")

                if settings.mt_require_clutch and state.ghostGear then
                    if padDownshiftHit or kbDownshiftHit or padUpshiftHit or kbUpshiftHit then
                        state.ghostGear = nil
                    end
                end

                if padUpshiftHit  and not isDPadHeld and not isHoldingInput(settings.mt_downshift_pad) and clutchSatisfied then
                    Gearbox.upshift(state, settings, inputManager)
                    if state.targetGear then state.pendingGear = state.targetGear; state.confirmTimer = 0.3; state.displayGear = state.targetGear end
                end
                if padDownshiftHit and not isDPadHeld and clutchSatisfied then
                    Gearbox.downshift(state, settings, inputManager)
                    if state.targetGear then state.pendingGear = state.targetGear; state.confirmTimer = 0.3; state.displayGear = state.targetGear end
                end
                if kbUpshiftHit   and clutchSatisfied then
                    Gearbox.upshift(state, settings, inputManager); changeHumanity(0.5)
                    if state.targetGear then state.pendingGear = state.targetGear; state.confirmTimer = 0.3; state.displayGear = state.targetGear end
                end
                if kbDownshiftHit and clutchSatisfied then
                    Gearbox.downshift(state, settings, inputManager)
                    if state.targetGear then state.pendingGear = state.targetGear; state.confirmTimer = 0.3; state.displayGear = state.targetGear end
                end

                if settings.mt_require_clutch then
                    if not state.ghostGear and state.currentGear > 0 and not state.shifting and state.targetGear == state.currentGear then
                        local isCoasting = not state.isAccelerating
                        if isClutchPedalHeld and isCoasting and not state.isHandbraking and not isSkidding then
                            local currentGearStats = state.vehicleStats and state.vehicleStats.gears[state.currentGear]
                            if currentGearStats and math.abs(state.speed) <= (currentGearStats.minSpeed + 1.0) then
                                state.ghostGear = state.currentGear
                                pcall(function() Game.MtClutchDisengage() end)
                            end
                        end
                    elseif state.ghostGear and not isClutchPedalHeld then
                        if state.persistentNeutralUI then
                            state.ghostGear = nil
                        else
                            local gearToRestore = state.ghostGear
                            state.ghostGear     = nil
                            local bypassRecovery = (state.currentGear <= 0 or state.isDecelerating)
                                or ((padUpshiftHit or kbUpshiftHit) and state.currentGear == 0)
                                or ((padDownshiftHit or kbDownshiftHit) and math.abs(state.speed) < 3.0)
                            if bypassRecovery and state.currentGear <= 0 then
                                -- stay in neutral/reverse
                            else
                                ExecuteRecoveryShift(gearToRestore)
                            end
                        end
                    else
                        if not state.isLocked then Gearbox.SetLock(state, true) end
                    end
                end

            -- ==========================
            -- BLUE  -  Shiftronic
            -- ==========================
            elseif state.raceMode == 1 then
                -- BLUE is handled by modules/shiftModes.lua.
                -- The old inline block dropped the lock, forced a gear, then
                -- re-locked 0.15s later inside a SetTimeout. Losing that callback
                -- wedged state.shifting true and killed all input. The module
                -- never locks at all, so there is no window and no callback.
                if state.blueAutoArmed == nil then state.blueAutoArmed = true end

                -- Lock state is owned by the module now: pinned = locked,
                -- handed-back-to-auto = unlocked. Do NOT force an unlock here.
                -- A blanket unlock every frame undid the pin the frame after a
                -- manual selection, so the game pulled you straight back to its
                -- own gear -- a 3rd->5th grab looked ignored when it had actually
                -- been applied and then immediately reverted.
                if not state.shifting and state.blueAutoArmed and state.isLocked then
                    Gearbox.SetLock(state, false)
                end

                if ShiftModes then
                    ShiftModes.blue(state, Gearbox, settings, {
                        up   = (kbUpshiftHit   or padUpshiftHit),
                        down = (kbDownshiftHit or padDownshiftHit),
                    }, checkInput)
                end

            -- ==========================
            -- RED  -  Hardcore H-Pattern sim
            -- ==========================
            else
                -- RED is handled by modules/shiftModes.lua.
                -- Red stays LOCKED so the game's auto box cannot shift for you --
                -- that is what keeps your shift audio, streaks and Dark Future
                -- hooks firing. The module sets the lock in the same frame as the
                -- gear, so there is no unlock window to desync in.
                if not state.shifting and not state.isLocked then
                    Gearbox.SetLock(state, true)
                end

                local clutchHeld = isHoldingInput(settings.mt_clutch_key) or analogClutchPressed
                state.clutchMode = clutchHeld and "disengaged" or "engaged"

                if ShiftModes then
                    local acted = ShiftModes.red(state, Gearbox, settings, clutchHeld, checkInput)
                    if acted then
                        if state.smLastShiftBad then
                            -- Rejected shift: streak reset, fail audio, penalties,
                            -- and the thermal / Dark Future hooks.
                            state.raceStreak  = 0
                            resetAudioMilestone()
                            changeHumanity(-3.0)
                            changeDFNerve(-2.0)
                            playShiftFail()
                            state.kickFlash   = 0.65
                            state.rejectFlash = 0
                            state.goodFlash   = 0
                            if thermalV12  then pcall(function() thermalV12.onBadShift()   end) end
                            if introSeq    then pcall(function() introSeq.onRedFail()      end) end
                            if voiceSystem then pcall(function() voiceSystem.onRedFailGhost() end) end
                        else
                            -- Clean shift: streak builds, reward audio scales with it.
                            state.raceStreak  = (state.raceStreak or 0) + 1
                            changeHumanity(2.0)
                            changeDFNerve(1.0)
                            playShiftReward(state.raceStreak)
                            if voiceSystem then pcall(function() voiceSystem.onCleanRedShift() end) end
                            state.rejectFlash = 0
                            state.kickFlash   = 0
                            -- Confirm window: show target, wait for blackboard to agree
                            state.pendingGear  = state.currentGear
                            state.displayGear  = state.currentGear
                            state.confirmTimer = 0.3
                            state.goodFlash    = 0  -- goodFlash fires on confirm, not here
                        end
                    end
                end
            end
            -- ---- legacy Red block below is now unreachable and kept only as
            -- ---- reference; it is skipped by the `end` above.
            if false then

                -- H-gate input -- numpad only; arrows reserved for blinkers
                local newGear = nil
                if     checkInput(settings.mt_gear1_key)          then newGear = 1
                elseif checkInput(settings.mt_gear2_key)          then newGear = 2
                elseif checkInput(settings.mt_gear3_key)          then newGear = 3
                elseif checkInput(settings.mt_gear4_key)          then newGear = 4
                elseif checkInput(settings.mt_gear5_key)          then newGear = 5
                elseif checkInput(settings.mt_gear6_key)          then newGear = 6
                elseif checkInput(settings.mt_racing_neutral_key) then newGear = -1
                elseif checkInput("IK_NumPadSubtract")            then newGear = 0  -- Reverse
                end

                if newGear ~= nil and newGear ~= state.currentGear then
                    local isNeutralTarget = (newGear == -1)
                    local isDownshift     = (newGear < state.currentGear)

                    if not clutchHeld then
                        -- No clutch = bad shift, no gear change
                        state.raceStreak  = 0
                        resetAudioMilestone()
                        changeHumanity(-3.0)
                        changeDFNerve(-2.0)
                        playShiftFail()
                        state.kickFlash   = 0.65
                        state.rejectFlash = 0
                        state.goodFlash   = 0
                        if thermalV12 then pcall(function() thermalV12.onBadShift() end) end
                        if introSeq   then pcall(function() introSeq.onRedFail()   end) end
                        if voiceSystem then pcall(function() voiceSystem.onRedFailGhost() end) end

                    elseif isNeutralTarget then
                        -- Neutral always allowed with clutch
                        state.shifting            = true
                        state.kbNeutralLocked     = true
                        state.persistentNeutralUI = true
                        Gearbox.SetLock(state, false)
                        pcall(function()
                            Game.MtClutchDisengage()
                            Game.MtSetRecoveryGear(-1)
                        end)
                        Gearbox.ForceGameShift(state, state.playerVehicle, -1)
                        state.currentGear = -1
                        eng.SetTimeout(0.15, function()
                            if state.inVehicle then
                                pcall(function() Game.MtClutchDisengage() end)
                                Gearbox.SetLock(state, true)
                                state.shifting = false
                            end
                        end)

                    elseif true then  -- Red H-Pattern: clutch held = driver owns speed matching
                        -- Good shift
                        state.shifting            = true
                        state.kbNeutralLocked     = false
                        state.persistentNeutralUI = false
                        Gearbox.SetLock(state, false)
                        if isDownshift and newGear >= 1 then
                            pcall(function() Game.MtSetThrottle(0.0) end)
                        end
                        pcall(function() Game.MtClutchDisengage() end)
                        Gearbox.ForceGameShift(state, state.playerVehicle, newGear)
                        state.currentGear = newGear
                        state.raceStreak  = (state.raceStreak or 0) + 1
                        changeHumanity(2.0)
                        changeDFNerve(1.0)
                        playShiftReward(state.raceStreak)
                        if voiceSystem then pcall(function() voiceSystem.onCleanRedShift() end) end
                        state.rejectFlash = 0
                        state.goodFlash   = 0.35
                        state.kickFlash   = 0
                        local ng = newGear
                        eng.SetTimeout(0.15, function()
                            if state.inVehicle then
                                pcall(function()
                                    Game.MtSetRecoveryGear(ng)
                                    Game.MtClutchEngage()
                                end)
                                Gearbox.SetLock(state, true)
                                state.shifting = false
                            end
                        end)

                    else
                        -- Bad shift: wrong gear for speed, kick to Neutral
                        state.raceStreak  = 0
                        resetAudioMilestone()
                        changeHumanity(-3.0)
                        playShiftFail()
                        state.kickFlash   = 0.65
                        state.rejectFlash = 0
                        state.goodFlash   = 0
                        state.shifting            = true
                        state.kbNeutralLocked     = true
                        state.persistentNeutralUI = true
                        Gearbox.SetLock(state, false)
                        Gearbox.ForceGameShift(state, state.playerVehicle, -1)
                        state.currentGear = -1
                        eng.SetTimeout(0.18, function()
                            if state.inVehicle then
                                pcall(function()
                                    Game.MtSetRecoveryGear(-1)
                                    Game.MtClutchDisengage()
                                end)
                                Gearbox.SetLock(state, true)
                                state.shifting = false
                            end
                        end)
                    end
                end
            end -- mode dispatch

            -- ---- THROTTLE GOVERNOR ----
            -- Restored from working V10 (its lines 712-713). V12 dropped this when
            -- the extra modes were added: clutchEngagement was still calculated and
            -- then never applied.
            --
            -- Without it, throttle is only ever written at discrete events, so any
            -- MtSetThrottle(0.0) is PERMANENT. Red's downshift sets 0.0 at ~1727 and
            -- its timeout restores only the recovery gear and clutch, never throttle
            -- -- which is "no power to the wheels, slowly decelerates", and why it
            -- stayed dead once it broke, in every mode, until a vehicle exit.
            --
            -- It also re-links the clutch to engine power, which has been dead in V12.
            --
            -- Written UNCONDITIONALLY every frame, exactly as V10 does it.
            --
            -- Do not add change-detection here. Red writes Game.MtSetThrottle(0.0)
            -- directly at its downshift, bypassing any cache. A cached "already 1.0"
            -- then skips the correcting write and the engine stays at 0.0 forever --
            -- power dies under acceleration in Red. The unconditional write is what
            -- makes every other direct throttle write in this file self-correcting.
            local finalEngagement = clutchEngagement or 1.0

            -- Engine-brake hold (Blue/Red downshifts, set by modules/shiftModes).
            -- Without this the governor would restore throttle the same frame the
            -- module lifted it, and engine braking would do nothing at all.
            -- It is a COUNTDOWN, so it always expires -- it cannot wedge throttle.
            if ShiftModes then ShiftModes.tick(state, dt) end
            if Clutch then Clutch.tick(state, settings, dt) end
            if (state.smBrakeHold or 0) > 0 then finalEngagement = 0.0 end

            state.currentThrottle = finalEngagement
            if state.isStalled then finalEngagement = 0.0 end

            pcall(function() Game.MtSetThrottle(finalEngagement) end)
        end -- isManualMode
    end -- settings.enabled

    -- ---- UI refresh ----
    if not state.lastUIClutchMode then state.lastUIClutchMode = "engaged" end
    local needsUIUpdate = state.currentGear  ~= state.lastGearInteger
        or state.isManualMode  ~= state.lastManualState
        or state.clutchMode    ~= state.lastUIClutchMode
        or state.raceMode      ~= state.lastUIRaceMode   -- FIX 2026-08-04 (B)
        or (state.kickFlash    or 0) > 0
        or (state.goodFlash    or 0) > 0
        or (state.rejectFlash  or 0) > 0
    if needsUIUpdate then
        UpdateGearUI()
        state.lastGearInteger   = state.currentGear
        state.lastManualState   = state.isManualMode
        state.lastUIClutchMode  = state.clutchMode
        state.lastUIRaceMode    = state.raceMode         -- FIX 2026-08-04 (B)
    end

    -- ---- THERMAL GUI HEARTBEAT ----
    -- updateAuxWidgets() (heat / stress / adrenaline / brake heat) sits inside
    -- UpdateGearUI, which only runs on a gear, mode, clutch or flash change.
    -- So the thermal dots only ever redrew when you shifted -- heat climbed in
    -- thermalV12 while the dot sat still. They need their own clock.
    --
    -- 10Hz, not per-frame: these are coloured dots, and each refresh does a
    -- SetText + SetTintColor per widget. 10Hz is smooth and ~6x cheaper.
    state.auxTimer = (state.auxTimer or 0) + dt
    if state.auxTimer >= 0.1 then
        state.auxTimer = 0
        pcall(updateAuxWidgets)
    end
end)