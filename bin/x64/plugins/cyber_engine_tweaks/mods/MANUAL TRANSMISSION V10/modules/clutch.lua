local Clutch = {}

function Clutch.updateState(state, settings, inputManager, isHoldingInput, neutralToggleHit, shiftHit, dt, isSkidding, isBike)
    if state.entryGrace > 0 then return end

    if shiftHit then
        state.kbNeutralLocked = false
        state.persistentNeutralUI = false
    end
    
    local digitalClutchPressed = isHoldingInput(settings.mt_clutch_key)
    local axisKey = settings.mt_clutch_axis or ""
    -- FIX 2026-08-07: inputManager is nil when called from Green (shiftModes.lua).
    -- Previous code indexed inputManager.axisValues unconditionally -- crash if
    -- the player has an analog clutch axis configured and is in Green mode.
    -- Guard added: treat as zero axis input when inputManager is unavailable.
    local axisRaw = 0
    if axisKey ~= "" and inputManager and inputManager.axisValues then
        axisRaw = inputManager.axisValues[axisKey] or 0
    end
    local currentClutchAmt = math.max(0, -axisRaw)
    local analogClutchPressed = (currentClutchAmt >= settings.mt_clutch_neutral_enter)
    
    local clutchSatisfiedForNeutral = not settings.mt_require_clutch or digitalClutchPressed or analogClutchPressed

    if neutralToggleHit and clutchSatisfiedForNeutral and not isBike then
        state.kbNeutralLocked = not state.kbNeutralLocked
        if state.kbNeutralLocked then
            state.persistentNeutralUI = true
        end
    end
	
    local padDownshiftHeld = isHoldingInput(settings.mt_downshift_pad)

    if padDownshiftHeld and clutchSatisfiedForNeutral then
        if shiftHit then
            state.clutchHoldTimer = 0.0
        else
            state.clutchHoldTimer = (state.clutchHoldTimer or 0) + dt

            if state.clutchHoldTimer > 0.4 and not isBike then
                state.persistentNeutralUI = true
            end
        end
    else
        state.clutchHoldTimer = 0.0
    end

    if not settings.mt_require_clutch then
        state.digitalHold = false
        state.clutchAmount = 0.0
        state.analogWantsNeutral = false
        
        if state.kbNeutralLocked or (state.clutchHoldTimer > 0.4) or state.persistentNeutralUI then
            state.clutchMode = "disengaged"
        else
            state.clutchMode = "engaged"
        end
        return
    end

    state.digitalHold  = isHoldingInput(settings.mt_clutch_key)
    -- FIX 2026-08-07: removed duplicate axisKey/axisRaw declaration that
    -- shadowed the guarded block above and would crash on nil inputManager.
    -- axisRaw is already correctly computed above -- reuse it here.
    state.clutchAmount = math.max(0, -axisRaw)

    if state.clutchAmount >= settings.mt_clutch_neutral_enter then
        state.analogWantsNeutral = true
    elseif state.clutchAmount <= settings.mt_clutch_reengage_exit then
        state.analogWantsNeutral = false
    end
    
    if state.kbNeutralLocked or (state.clutchHoldTimer > 0.4) or state.persistentNeutralUI then
        state.clutchMode = "disengaged"
    else
        if state.clutchMode == "disengaged" then
            local escapeNeutral = shiftHit
            if not state.persistentNeutralUI then
                escapeNeutral = escapeNeutral or (state.clutchAmount <= settings.mt_clutch_reengage_exit and not state.digitalHold)
            end
            
            if escapeNeutral then
                state.persistentNeutralUI = false
                
                if state.clutchAmount >= settings.mt_clutch_slip_enter or state.digitalHold then
                    state.clutchMode = "slip"
                else
                    state.clutchMode = "engaged"
                end
            end
        else
            if state.clutchAmount >= settings.mt_clutch_slip_enter or state.digitalHold then
                state.clutchMode = "slip"
            else
                state.clutchMode = "engaged"
            end
        end
    end
end

-- Tick the keyboard clutch ramp and stall simulation.
-- Call this every frame from init.lua onUpdate, before getEngagementLevel.
-- raceMode: 0=Green, 1=Blue, 2=Red. Stall only fires on Green and Red.
function Clutch.tick(state, settings, dt)
    if not settings.mt_require_clutch then return end

    local held = state.digitalHold or false

    -- Ramp: held = disengage fast (0.1s), released = engage slow (0.5s)
    local current = state.clutchEngagementRamp or (held and 0.0 or 1.0)
    if held then
        current = math.max(0.0, current - dt / 0.10)
    else
        current = math.min(1.0, current + dt / 0.50)
    end
    state.clutchEngagementRamp = current

    -- Stall check: Blue (1) never. Red (2) always.
    -- Green (0): only when mt_green_stall_enabled is true (optional trainer toggle).
    local mode = state.raceMode or 0
    if mode == 1 then return end
    if mode == 0 and not (settings.mt_green_stall_enabled) then return end

    local spd = math.abs(state.speed or 0)
    if spd > 5.0 then
        state.isStalled = false
        return
    end

    -- Stalled already: hold stall until clutch is pressed in fully
    if state.isStalled then
        if current < 0.15 then
            state.isStalled = false  -- clutch in = recovery ready
        end
        pcall(function() Game.MtSetThrottle(0.0) end)
        return
    end

    -- Stall trigger: clutch releasing faster than throttle can match
    -- engagement > 0.4 means friction zone, throttle must be meeting it
    local throttle = state.currentThrottle or 0.0
    if current > 0.40 and throttle < (current * 0.55) and spd < 3.0 then
        state.isStalled = true
        pcall(function()
            Game.MtSetThrottle(0.0)
            Game.MtClutchDisengage()
        end)
    end
end

function Clutch.getEngagementLevel(state, settings)
    if not settings.mt_require_clutch then return 1.0 end

    -- Keyboard: use ramp value instead of binary digitalHold
    if state.digitalHold then return 0.0 end
    if state.clutchEngagementRamp ~= nil and state.clutchAmount <= settings.mt_clutch_slip_enter then
        return state.clutchEngagementRamp
    end

    local ca = state.clutchAmount
    local slipStart = settings.mt_clutch_slip_enter
    local neutralStart = settings.mt_clutch_neutral_enter

    local engagement = 0.0

    if ca <= slipStart then 
        engagement = 1.0 
    elseif ca >= neutralStart then 
        engagement = 0.0 
    else
        local range = neutralStart - slipStart
        if range > 0.001 then
            local fraction = (ca - slipStart) / range
            engagement = math.max(0, math.min(1, 1.0 - fraction))
        end
    end

    local isBike = state.playerVehicle and state.playerVehicle:IsA(CName("vehicleBikeBaseObject"))
    
    if isBike and state.isAccelerating and state.currentGear > 0 then
        local minCOMOffset = 0.1 
        local minPitchAngle = 5.0 
        
        local success, isWheelie = pcall(function()
            return state.playerVehicle:IsPerformingAWheelieOrEndo(minCOMOffset, minPitchAngle)
        end)

        -- FIX 2026-08-07: pcall can succeed but return a non-boolean on vehicles
        -- that don't support this method. Type-check before branching.
        if success and type(isWheelie) == "boolean" and isWheelie and ca < 0.95 then
            local wheelieTargetPower = 0.85
            
            local successPitch, pitchAngle = pcall(function()
                local forward = state.playerVehicle:GetWorldForward()
                return math.asin(forward.z) * (180 / math.pi)
            end)

            if successPitch and type(pitchAngle) == "number" then
                local dynamicCap = 1.0

                if pitchAngle > 40.0 then
                    local overPitch = pitchAngle - 40.0
                    local pitchPenalty = (overPitch / 6.0) * 0.15 
                    dynamicCap = math.max(0.85, 1.0 - pitchPenalty)
                end

                local targetSpeedLimit = 27.0 
                local currentAbsSpeed = math.abs(state.speed)
                if currentAbsSpeed > targetSpeedLimit then
                    local speedOverage = currentAbsSpeed - targetSpeedLimit
                    local speedPenalty = (speedOverage / 5.0) * 0.15
                    dynamicCap = math.max(0.60, dynamicCap - speedPenalty)
                end

                wheelieTargetPower = dynamicCap
            end
            
            if ca == 0 then
                engagement = math.min(engagement, wheelieTargetPower)
            else
                engagement = math.max(engagement, wheelieTargetPower)
            end
        end
    end
	
    return engagement
end

return Clutch