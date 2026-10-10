local utils = {}

local t_new = nil
if table.new then
    t_new = table.new
else
    local ok, func = pcall(require, "table.new")
    if ok and type(func) == "function" then
        t_new = func
    else
        t_new = function(a, b) return {} end
    end
end

local t_clear = nil
if table.clear then
    t_clear = table.clear
else
    local ok, func = pcall(require, "table.clear")
    if ok and type(func) == "function" then
        t_clear = func
    else
        t_clear = function(t) 
            if t then 
                for k in pairs(t) do t[k] = nil end 
            end 
        end
    end
end

local vehicleCache = t_new(0, 20)

local GearWidget = nil
local InkHUDLayer = nil
local DigitalFont = "base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily"

local colorGreen = nil
local colorRed   = nil
local colorYellow= nil

local cachedStatsSystem = nil
local cachedSettingsSystem = nil
local cachedInkSystem = nil
local cachedGearWidget = nil

local cachedResWidth = 0
local cachedResHeight = 0
local cachedMargin = nil

local GRAVITY = 9.81
local SPEED_UNIT_TO_MS = 1.073682

local gearStringCache = {
    [-1] = "N",
    [0]  = "R",
    [1]  = "1",
    [2]  = "2",
    [3]  = "3",
    [4]  = "4",
    [5]  = "5",
    [6]  = "6",
    [7]  = "7"
}

function utils.isInVehicle()
    local player = Game.GetPlayer()
    if not player then return false end
    return Game.GetMountedVehicle(player) ~= nil
end

function utils.isDriver()
    local player = Game.GetPlayer()
    if not player then return false end

    local mountingFacility = Game.GetMountingFacility()
    if not mountingFacility then return false end

    local mountingInfo = mountingFacility:GetMountingInfoSingleWithIds(player:GetEntityID())
    local parentId = mountingInfo.parentId
    local slotID = mountingInfo.slotId.id
    local slotName = Game.NameToString(slotID)

    if parentId.hash ~= 0 and slotName == "seat_front_left" then
        return true
    end

    return false
end

function utils.calculateBrakingDeceleration(data)
    if not data or data.mass == 0 then return 0 end

    local mechanicalForce = (data.MaxTorque / data.WheelRadius) * data.BrakingFriction
    local gripLimitForce = data.mass * GRAVITY * data.TireGrip
    local actualBrakingForce = math.min(mechanicalForce, gripLimitForce)
    local deceleration_ms2 = actualBrakingForce / data.mass
    local base_X = deceleration_ms2 / SPEED_UNIT_TO_MS
    
    return base_X
end

function utils.getVehicleGearData()
    local player = Game.GetPlayer()
    local vehicleEntity = Game.GetMountedVehicle(player)

    if not vehicleEntity then return nil end

    local vehicleRecord = vehicleEntity:GetRecord()
    if not vehicleRecord then return nil end

    local recordID = tostring(vehicleRecord:GetRecordID())
    
    if vehicleCache[recordID] ~= nil then
        return vehicleCache[recordID]
    end
    
    local engineData = vehicleRecord:VehEngineData()
    
    local driveModel
    if vehicleEntity:IsA(CName("vehicleBikeBaseObject")) then
        driveModel = vehicleRecord:BikeDriveModelData()
    else
        driveModel = vehicleRecord:VehDriveModelData()
    end

    if not engineData or not driveModel then return nil end
    
    local data = t_new(0, 20)

    data.gearChangeTime = engineData:GearChangeTime()
    data.gearChangeCooldown = engineData:GearChangeCooldown()
    data.reverseDirDelay = engineData:ReverseDirDelay()
    
    data.engineMaxTorque = engineData:EngineMaxTorque()
    data.resistanceTorque = engineData:ResistanceTorque()
    data.wheelsResistanceRatio = engineData:WheelsResistanceRatio()
    data.flyWheelInertia = engineData:FlyWheelMomentOfInertia()
    data.finalGearTorqueDecimationScalor = engineData:FinalGearTorqueDecimationScalor()
    
    data.minRPM = engineData:MinRPM()
    data.maxRPM = engineData:MaxRPM()
    data.gearCurvesPath = engineData:GearCurvesPath()
    data.fastR1GearChange = engineData:FastR1GearChange()
    data.forceReverseRPMToMin = engineData:ForceReverseRPMToMin()
   
    data.mass = driveModel:Total_mass()
    data.Aero = driveModel:AirResistanceFactor()
    data.BrakingFriction = driveModel:BrakingFrictionFactor()
    
    local drivingSetup = driveModel:WheelSetup()
    if drivingSetup then
        local frontDriving = drivingSetup:FrontPresetHandle()
        local backDriving = drivingSetup:BackPresetHandle()

        if frontDriving and backDriving then
            local frontTorque = frontDriving:MaxBrakingTorque()
            local backTorque = backDriving:MaxBrakingTorque()
            local frontGrip = frontDriving:FrictionMulLongitudinal()
            local backGrip = backDriving:FrictionMulLongitudinal()
            
            data.MaxTorque = frontTorque + backTorque
            data.TireGrip = (frontGrip + backGrip) / 2
        else
            data.MaxTorque = 1000 
            data.TireGrip = 1.0
        end
    end
    
    local dimensionsSetup = vehicleRecord:VehWheelDimensionsSetup()
    if dimensionsSetup then
        local frontDimensions = dimensionsSetup:FrontPresetHandle()
        local backDimensions = dimensionsSetup:BackPresetHandle()
        
        if frontDimensions and backDimensions then
            local frontRadius = frontDimensions:TireRadius()
            local backRadius = backDimensions:TireRadius()
            
            data.WheelRadius = frontRadius
            data.BackWheelRadius = backRadius
            data.AverageWheelRadius = (frontRadius + backRadius) / 2
        else
            data.WheelRadius = 0.35
        end
    end
    
    local gearsCount = engineData:GetGearsCount()
    data.gearsCount = gearsCount
    -- ---- GEAR TABLE INDEXING ----
    -- Engine gear RECORDS are 0-based: GetGearsItem(0) is 1st gear.
    -- Every consumer here reads them 1-based: gears[1] for 1st, `for i = 1, count`
    -- in GetBestGearForSpeed, and `#gears` as the ceiling in Gearbox.upshift.
    --
    -- Storing at [i] misaligned everything by one gear:
    --   * gears[1] held 2nd gear's record, so 1st was tested against 2nd's
    --     minSpeed -- below that speed the upshift silently returned
    --   * #gears returned gearsCount-1 (a [0] key sits outside the sequence),
    --     so `targetGear > #gears` blocked the TOP gear entirely, in every mode
    --
    -- Storing at [i + 1] aligns record 0 to gears[1] and makes #gears correct.
    data.gears = t_new(gearsCount, 1)

    for i = 0, gearsCount - 1 do
        local gearRecord = engineData:GetGearsItem(i)
        
        if gearRecord ~= nil then
            local gearInfo = t_new(0, 6)
            gearInfo.index = i
            gearInfo.maxSpeed = gearRecord:MaxSpeed()
            gearInfo.maxEngineRPM = gearRecord:MaxEngineRPM()
            gearInfo.minSpeed = gearRecord:MinSpeed()
            gearInfo.minEngineRPM = gearRecord:MinEngineRPM()
            gearInfo.torqueMultiplier = gearRecord:TorqueMultiplier()

            data.gears[i + 1] = gearInfo
        end
    end

    vehicleCache[recordID] = data
    return data
end

function utils.clearCache()
    t_clear(vehicleCache)
    
    cachedStatsSystem = nil
    cachedSettingsSystem = nil
    cachedInkSystem = nil
    
    utils.forceUIReload()
end

function utils.forceUIReload()
    cachedGearWidget = nil 
    cachedInkSystem = nil
    cachedMargin = nil
    cachedResWidth = 0
    cachedResHeight = 0
end

function utils.updateGearWidgetMargin(widget)
    if not widget then return end
    
    local width, height = GetDisplayResolution()
    if not width or not height then return end

    if width ~= cachedResWidth or height ~= cachedResHeight or not cachedMargin then
        cachedResWidth = width
        cachedResHeight = height
        
        local X_MULTIPLIER = 0.30 
        local Y_MULTIPLIER = 0.161 
        
        local xOffset = height * X_MULTIPLIER 
        local yOffset = height * Y_MULTIPLIER 
        
        cachedMargin = inkMargin.new({ left = xOffset, top = 0, right = 0, bottom = yOffset })
    end
    
    pcall(function() 
        widget:SetMargin(cachedMargin) 
    end)
end

function utils.getOrCreateGearWidget(gearInput, visible, isFPP, forceShowFPP, showTPP)
    if not GearWidget then
        GearWidget = StringToName("GearWidget")
        InkHUDLayer = StringToName("inkHUDLayer")
        colorGreen = HDRColor.new({ Red = 0.0, Green = 1.0, Blue = 0.0, Alpha = 1 })
        colorRed   = HDRColor.new({ Red = 1.0, Green = 0.0, Blue = 0.0, Alpha = 1 })
        colorYellow= HDRColor.new({ Red = 1.0, Green = 1.0, Blue = 0.0, Alpha = 1 })
    end

    if cachedGearWidget then
         if not cachedGearWidget.SetText then 
             cachedGearWidget = nil 
         end
    end

    if not cachedGearWidget then
        if not cachedInkSystem then cachedInkSystem = Game.GetInkSystem() end
        
        local hudLayer = cachedInkSystem:GetLayer(InkHUDLayer)
        if not hudLayer then return nil end

        local container = hudLayer:GetVirtualWindow() 
        if not container then return nil end

        local existingWidget = container:GetWidget(GearWidget)

        if existingWidget then
            container:RemoveChild(existingWidget)
        end

        local widget = inkText.new()
        widget:SetName(GearWidget)
        widget:SetFontFamily(DigitalFont) 
        widget:SetFontSize(80)
        widget:SetAnchor(inkEAnchor.BottomLeft)
        widget:SetAnchorPoint(0.5, 0.5)
        widget:Reparent(container, -1) 
        
        cachedGearWidget = widget
    end

    if not cachedGearWidget or not cachedGearWidget.SetText then return nil end

    local text = ""
    local tint = colorGreen

    if type(gearInput) == "number" then
        text = gearStringCache[gearInput] or tostring(gearInput)
        if gearInput == 0 then
            tint = colorRed
        elseif gearInput == -1 then
            tint = colorYellow
        end
    else
        text = tostring(gearInput)
        if text == "R" then
            tint = colorRed
        elseif text == "N" then
            tint = colorYellow
        end
    end

    cachedGearWidget:SetText(text)
    cachedGearWidget:SetTintColor(tint)

    local forcedFPP = (forceShowFPP == true)
    local forcedTPP = (showTPP == true)
    if showTPP == nil then forcedTPP = true end
    
    local shouldShow = false
    if visible then
        if isFPP then
            shouldShow = forcedFPP
        else
            shouldShow = forcedTPP
        end
    end
    
    cachedGearWidget:SetVisible(shouldShow)
    
    if shouldShow then
        utils.updateGearWidgetMargin(cachedGearWidget)
    end

    return cachedGearWidget
end

function utils.getDisplaySpeed(velocity)
    local absVel = math.abs(velocity)

    if not cachedStatsSystem then
        cachedStatsSystem = Game.GetGameInstance():GetStatsDataSystem()
    end
    
    local curveMult = 1.0
    if cachedStatsSystem then
        curveMult = cachedStatsSystem:GetValueFromCurve("vehicle_ui", absVel, "speed_to_multiplier")
    end

    if not cachedSettingsSystem then
        cachedSettingsSystem = Game.GetGameInstance():GetSettingsSystem()
    end
    
    local useKph = false
    
    if cachedSettingsSystem then
        local uiGroup = cachedSettingsSystem:GetGroup("/interface")
        if uiGroup then
            local unitVar = uiGroup:GetVar("SpeedometerUnits")
            if unitVar and unitVar:GetIndex() ~= 0 then 
                useKph = true 
            end
        end
    end
    
    local convFactor = 1.0
    if useKph then
        convFactor = 1.60934
    end
    
    return math.floor(absVel * curveMult * convFactor)
end

utils.speedToSpeedometerUnits = utils.getDisplaySpeed

return utils