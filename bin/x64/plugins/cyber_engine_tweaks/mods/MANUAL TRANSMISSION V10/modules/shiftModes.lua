-- ============================================================================
-- modules/shiftGreen.lua
-- Green (Sequential) shifting for MANUAL TRANSMISSION V10 / V12
--
-- Extracted from init.lua. Handles all Green mode input and clutch logic.
-- Called from init.lua when state.raceMode == 0.
--
-- Interface:
--   ShiftGreen.tick(state, Gearbox, Clutch, settings, inputs, callbacks, dt)
--     inputs    = { kbUp, kbDown, padUp, padDown, isDPadHeld, isHoldingInput,
--                   kbNeutralHit, clutchSatisfied, isClutchPedalHeld,
--                   isSkidding, isBike }
--     callbacks = { changeHumanity, ExecuteRecoveryShift,
--                   setPendingGear }
--   Returns: clutchEngagement (always 1.0 -- sequential never cuts throttle)
--
-- DESIGN RULES:
--   - Clutch is cosmetic only in Green. Never gates shifts. Never cuts throttle.
--   - Bikes: sequential lock enforced, no mode change allowed.
--   - Stall simulation: disabled (handled by clutch.lua Red-only guard).
--   - Repeat-fire guard: confirmTimer blocks double-fire on held key.
--
-- Lua 5.1 / LuaJIT. Pure ASCII.
-- ============================================================================

local ShiftGreen = {}

-- ---------------------------------------------------------------- INTERNAL ---

local function greenLog(line)
    pcall(function()
        local f = io.open("green_debug.txt", "a")
        if f then
            f:write(os.date("%H:%M:%S") .. "  " .. tostring(line) .. "\n")
            f:close()
        end
    end)
end

-- ------------------------------------------------------------------ PUBLIC ---

-- Called every frame from init.lua when raceMode == 0.
-- Returns clutchEngagement (always 1.0 for Green).
function ShiftGreen.tick(state, Gearbox, Clutch, settings, inputs, callbacks, dt)

    -- Lock must be held in Green so game auto-box cannot shift for us
    if not state.shifting and not state.isLocked then
        Gearbox.SetLock(state, true)
    end

    -- Clutch state update -- cosmetic only, bar widget reads from state
    local safeKbNeutralHit = inputs.kbNeutralHit and inputs.clutchSatisfied
    local function safeIsHoldingInput(keyName)
        if (keyName == settings.mt_downshift_pad or keyName == settings.mt_neutral_key)
        and not inputs.clutchSatisfied then return false end
        return inputs.isHoldingInput(keyName)
    end

    local postComboShiftHit = inputs.kbUp or inputs.kbDown or inputs.padUp or inputs.padDown
    local postComboValid    = postComboShiftHit and inputs.clutchSatisfied
    Clutch.updateState(state, settings, nil, safeIsHoldingInput,
        safeKbNeutralHit, postComboValid, dt, inputs.isSkidding, inputs.isBike)

    -- Throttle: sequential never cuts power based on clutch position
    local clutchEngagement = 1.0

    -- Ghost gear clear on any shift input when clutch required
    if settings.mt_require_clutch and state.ghostGear then
        if inputs.padDown or inputs.kbDown or inputs.padUp or inputs.kbUp then
            state.ghostGear = nil
        end
    end

    -- Pad shifts -- no clutch gate
    if inputs.padUp and not inputs.isDPadHeld and not inputs.isHoldingInput(settings.mt_downshift_pad) then
        Gearbox.upshift(state, settings, nil)
        if state.targetGear then callbacks.setPendingGear(state.targetGear) end
    end
    if inputs.padDown and not inputs.isDPadHeld then
        Gearbox.downshift(state, settings, nil)
        if state.targetGear then callbacks.setPendingGear(state.targetGear) end
    end

    -- Keyboard shifts -- confirm window guard prevents repeat-fire on held key
    local greenOk = (state.confirmTimer or 0) <= 0
    if inputs.kbUp and greenOk then
        Gearbox.upshift(state, settings, nil)
        if callbacks.changeHumanity then callbacks.changeHumanity(0.5) end
        if state.targetGear then callbacks.setPendingGear(state.targetGear) end
        greenLog(string.format("KB UP: cur=%s target=%s spd=%.1f",
            tostring(state.currentGear), tostring(state.targetGear), math.abs(state.speed or 0)))
    end
    if inputs.kbDown and greenOk then
        Gearbox.downshift(state, settings, nil)
        if state.targetGear then callbacks.setPendingGear(state.targetGear) end
        greenLog(string.format("KB DOWN: cur=%s target=%s spd=%.1f",
            tostring(state.currentGear), tostring(state.targetGear), math.abs(state.speed or 0)))
    end

    -- Ghost gear (clutch coast / re-engage) -- only when clutch required
    if settings.mt_require_clutch then
        if not state.ghostGear and state.currentGear > 0
        and not state.shifting and state.targetGear == state.currentGear then
            local isCoasting = not state.isAccelerating
            if inputs.isClutchPedalHeld and isCoasting
            and not state.isHandbraking and not inputs.isSkidding then
                local gearStats = state.vehicleStats and state.vehicleStats.gears[state.currentGear]
                if gearStats and math.abs(state.speed) <= (gearStats.minSpeed + 1.0) then
                    state.ghostGear = state.currentGear
                    pcall(function() Game.MtClutchDisengage() end)
                end
            end
        elseif state.ghostGear and not inputs.isClutchPedalHeld then
            if state.persistentNeutralUI then
                state.ghostGear = nil
            else
                local gearToRestore = state.ghostGear
                state.ghostGear     = nil
                local bypassRecovery = (state.currentGear <= 0 or state.isDecelerating)
                    or ((inputs.padUp or inputs.kbUp) and state.currentGear == 0)
                    or ((inputs.padDown or inputs.kbDown) and math.abs(state.speed) < 3.0)
                if bypassRecovery and state.currentGear <= 0 then
                    -- stay in neutral/reverse
                else
                    if callbacks.ExecuteRecoveryShift then
                        callbacks.ExecuteRecoveryShift(gearToRestore)
                    end
                end
            end
        else
            if not state.isLocked then Gearbox.SetLock(state, true) end
        end
    end

    return clutchEngagement
end

-- ============================================================================
-- BLUE  -  Shiftronic
-- Arrow = sequential step. Numpad = free-jump, no penalty, no clutch gate.
-- Uses eng.SetTimeout like Red so shiftTimeout doesn't block its own inputs.
-- interface: ShiftModes.blue(state, Gearbox, settings, inputs, checkInput, eng)
-- ============================================================================
local function blueTick(state, Gearbox, settings, inputs, checkInput, eng)
    -- Numpad free-jump -- no shifting guard, Shiftronic accepts input freely
    local numTarget = nil
    if     checkInput(settings.mt_gear1_key)          then numTarget = 1
    elseif checkInput(settings.mt_gear2_key)          then numTarget = 2
    elseif checkInput(settings.mt_gear3_key)          then numTarget = 3
    elseif checkInput(settings.mt_gear4_key)          then numTarget = 4
    elseif checkInput(settings.mt_gear5_key)          then numTarget = 5
    elseif checkInput(settings.mt_gear6_key)          then numTarget = 6
    elseif checkInput(settings.mt_gear7_key)          then numTarget = 7
    elseif checkInput(settings.mt_racing_neutral_key) then numTarget = -1
    end

    if numTarget ~= nil and numTarget ~= state.currentGear then
        Gearbox.SetLock(state, false)
        Gearbox.ForceGameShift(state, state.playerVehicle, numTarget)
        Gearbox.ForceGameSync(state, state.playerVehicle)
        state.currentGear   = numTarget
        state.targetGear    = numTarget
        state.shifting      = true
        state.shiftTimeout  = 0.20
        state.blueAutoArmed = false
        eng.SetTimeout(0.20, function()
            if state.inVehicle and state.raceMode == 1 then
                Gearbox.SetLock(state, true)
                state.shifting = false
            end
        end)
        return true
    end

    -- Arrow sequential -- no shifting guard
    if inputs.up then
        local target = (state.currentGear <= 0) and 1 or (state.currentGear + 1)
        local maxGear = (state.vehicleStats and state.vehicleStats.gears)
            and #state.vehicleStats.gears or 8
        if target <= maxGear then
            Gearbox.SetLock(state, false)
            Gearbox.ForceGameShift(state, state.playerVehicle, target)
            Gearbox.ForceGameSync(state, state.playerVehicle)
            state.currentGear   = target
            state.targetGear    = target
            state.shifting      = true
            state.shiftTimeout  = 0.20
            state.blueAutoArmed = false
            return true
        end
    elseif inputs.down and state.currentGear > 1 then
        local target = state.currentGear - 1
        Gearbox.SetLock(state, false)
        Gearbox.ForceGameShift(state, state.playerVehicle, target)
        Gearbox.ForceGameSync(state, state.playerVehicle)
        state.currentGear   = target
        state.targetGear    = target
        state.shifting      = true
        state.shiftTimeout  = 0.20
        state.blueAutoArmed = false
        return true
    end

    return false
end

-- ============================================================================
-- RED  -  H-Pattern
-- Lifted verbatim from the working legacy block in init (lines 1839-1946).
-- eng passed in so SetTimeout works. Penalties/audio handled by init's acted block.
-- Returns true if a gear was attempted, false if no input.
-- Sets state.smLastShiftBad true on bad shift, false on clean.
-- ============================================================================
local function redTick(state, Gearbox, settings, clutchHeld, checkInput, eng)
    local newGear = nil
    if     checkInput(settings.mt_gear1_key)          then newGear = 1
    elseif checkInput(settings.mt_gear2_key)          then newGear = 2
    elseif checkInput(settings.mt_gear3_key)          then newGear = 3
    elseif checkInput(settings.mt_gear4_key)          then newGear = 4
    elseif checkInput(settings.mt_gear5_key)          then newGear = 5
    elseif checkInput(settings.mt_gear6_key)          then newGear = 6
    elseif checkInput(settings.mt_gear7_key)          then newGear = 7
    elseif checkInput(settings.mt_racing_neutral_key) then newGear = -1
    elseif checkInput(settings.mt_gear_reverse_key)   then
        if state.currentGear == -1 and clutchHeld
        and math.abs(state.speed or 0) < 2.0 then
            newGear = 0
        end
    end

    if newGear == nil or newGear == state.currentGear then return false end

    local isNeutralTarget = (newGear == -1)
    local isDownshift     = (newGear < state.currentGear)

    if not clutchHeld then
        -- Bad shift: no clutch
        state.smLastShiftBad = true
        return true
    end

    if isNeutralTarget then
        -- Neutral always allowed with clutch
        state.smLastShiftBad      = false
        state.shifting            = true
        state.shiftTimeout        = 0.20
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
        return true
    end

    -- Clean shift
    state.smLastShiftBad      = false
    state.shifting            = true
    state.shiftTimeout        = 0.20
    state.kbNeutralLocked     = false
    state.persistentNeutralUI = false
    Gearbox.SetLock(state, false)
    if isDownshift and newGear >= 1 then
        pcall(function() Game.MtSetThrottle(0.0) end)
    end
    pcall(function() Game.MtClutchDisengage() end)
    Gearbox.ForceGameShift(state, state.playerVehicle, newGear)
    state.currentGear = newGear
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
    return true
end

-- ============================================================================
-- TICK  -  engine brake hold countdown
-- ============================================================================
local function modeTick(state, dt)
    if (state.smBrakeHold or 0) > 0 then
        state.smBrakeHold = math.max(0, state.smBrakeHold - dt)
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================
return {
    tick  = modeTick,
    blue  = blueTick,
    red   = redTick,
    green = ShiftGreen.tick,
}