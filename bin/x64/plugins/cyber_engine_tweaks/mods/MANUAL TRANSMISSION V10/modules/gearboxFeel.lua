-- ============================================================================
-- RACERS DELIGHT ENGINE - MODULE: gearbox.lua
-- Description: Drivetrain Inertia Smoothing & Thermal State Degradation Loop
-- Target Framework: Cyber Engine Tweaks (CET)
-- ============================================================================

local gearbox = {
    -- Configuration Parameters (Adjustable to fine-tune feel)
    config = {
        flywheelInertia = 0.15,      -- Rotational mass feel (0.05 = light racing, 0.25 = heavy flywheel)
        throttleSmoothing = 7.5,     -- Rate of throttle input transition (higher = snappier)
        thermalTickRate = 0.5,       -- State update interval in seconds (preserves 25-33 FPS baseline)
        maxTempThreshold = 100.0,    -- Temp (°C) before friction drop & shift delay kick in
        tempCoolRate = 4.0,          -- Heat dissipation rate per second
        tempHeatRate = 16.0,         -- Thermal buildup rate during high RPM slipping
    },

    -- Internal Telemetry State
    state = {
        targetThrottle = 0.0,
        smoothedThrottle = 0.0,
        transTemp = 20.0,            -- Ambient starting temp (°C)
        lastThermalTick = 0.0,
        isOverheated = false,
        shiftDelayModifier = 1.0,    -- 1.0 = normal engagement speed, >1.0 = delayed engagement
    }
}

--- Initialize Module State
function gearbox.init()
    gearbox.state.smoothedThrottle = 0.0
    gearbox.state.transTemp = 20.0
    gearbox.state.lastThermalTick = 0.0
    gearbox.state.shiftDelayModifier = 1.0
    print("[Racers Delight] gearbox.lua loaded successfully.")
end

--- Drivetrain Inertia Filter
-- Smooths raw pedal input to emulate flywheel mass and shaft lash before sending to NCGT
-- @param rawThrottle number (0.0 to 1.0)
-- @param deltaTime number Frame time step
-- @return number Filtered throttle input
function gearbox.updateThrottleInertia(rawThrottle, deltaTime)
    gearbox.state.targetThrottle = rawThrottle

    -- Exponential smoothing algorithm to cushion abrupt throttle snaps
    local blendFactor = 1.0 - math.exp(-gearbox.config.throttleSmoothing * deltaTime / (1.0 + gearbox.config.flywheelInertia))
    gearbox.state.smoothedThrottle = gearbox.state.smoothedThrottle + (gearbox.state.targetThrottle - gearbox.state.smoothedThrottle) * blendFactor

    return gearbox.state.smoothedThrottle
end

--- Thermal & Transmission State Loop
-- Executes on a low-tick clock to avoid taxing frame times
-- @param currentRPM number Engine RPM
-- @param isClutchActive boolean Whether clutch gate is engaged
-- @param vehicleSpeed number Speed metric
-- @param deltaTime number Frame time step
function gearbox.updateThermalState(currentRPM, isClutchActive, vehicleSpeed, deltaTime)
    gearbox.state.lastThermalTick = gearbox.state.lastThermalTick + deltaTime

    -- Throttle update rate to tick interval
    if gearbox.state.lastThermalTick < gearbox.config.thermalTickRate then
        return
    end

    local interval = gearbox.state.lastThermalTick
    gearbox.state.lastThermalTick = 0.0

    -- Detect friction conditions (holding clutch high in powerband at low speeds)
    local isSlipping = (isClutchActive and currentRPM > 3800 and vehicleSpeed < 12.0)

    if isSlipping then
        gearbox.state.transTemp = math.min(
            gearbox.config.maxTempThreshold + 25.0, 
            gearbox.state.transTemp + (gearbox.config.tempHeatRate * interval)
        )
    else
        gearbox.state.transTemp = math.max(
            20.0, 
            gearbox.state.transTemp - (gearbox.config.tempCoolRate * interval)
        )
    end

    -- Apply mechanical punishment if pushed past limits
    if gearbox.state.transTemp >= gearbox.config.maxTempThreshold then
        gearbox.state.isOverheated = true
        gearbox.state.shiftDelayModifier = 1.35 -- 35% slower shift speed due to thermal drag
    else
        gearbox.state.isOverheated = false
        gearbox.state.shiftDelayModifier = 1.0
    end
end

--- Telemetry Data Hook for On-Screen Debugging
function gearbox.getTelemetry()
    return gearbox.state
end

return gearbox