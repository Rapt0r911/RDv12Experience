local holdTime = 0.5

local input = {
    listeningKeybindWidget = nil,
    inputListener = nil,
    bindings = {},
    activeKeys = {},
    axisValues = {},
    nuiTables = {}
}

local function handleInput(event)
    local key = event:GetKey().value
    local action = event:GetAction().value

    if input.listeningKeybindWidget and key:find("IK_Pad") and action == "IACT_Release" then
        input.listeningKeybindWidget:OnKeyBindingEvent(KeyBindingEvent.new({keyName = key}))
        input.listeningKeybindWidget = nil
    elseif input.listeningKeybindWidget and action == "IACT_Release" then
        input.listeningKeybindWidget = nil
    end

    if action == "IACT_Press" then
        input.activeKeys[key] = 0
    else
        input.activeKeys[key] = nil
    end
end

local function handleAxis(event)
    local key = event:GetKey().value
    local value = event:GetValue() 

    if input.listeningKeybindWidget and math.abs(value) > 0.5 then 
        input.listeningKeybindWidget:OnKeyBindingEvent(KeyBindingEvent.new({keyName = key}))
        input.listeningKeybindWidget = nil
    end

    if math.abs(value) > 0.05 then
        input.axisValues[key] = value 
    else
        input.axisValues[key] = nil
    end
end

function input.onHook()
    input.inputListener = NewProxy({
        OnKeyInput = {
            args = {'handle:KeyInputEvent'},
            callback = handleInput
        },
        OnAxisInput = {
            args = {'handle:AxisInputEvent'},
            callback = handleAxis
        }
    })

    input.callbackID = Game.GetCallbackSystem():RegisterCallback('Input/Key', input.inputListener:Target(), input.inputListener:Function("OnKeyInput"), true)
    input.axisCallbackID = Game.GetCallbackSystem():RegisterCallback('Input/Axis', input.inputListener:Target(), input.inputListener:Function("OnAxisInput"), true)
    
    Observe("SettingsSelectorControllerKeyBinding", "ListenForInput", function(this) 
        input.listeningKeybindWidget = this
    end)
end

function input.onUpdate(deltaTime)
    for key, time in pairs(input.activeKeys) do
        input.activeKeys[key] = time + deltaTime
    end

    for _, binding in pairs(input.bindings) do
        local allPressed = true
        local keys = binding.keys
        
        for i = 1, #keys do
            local keyInfo = keys[i]
            local keyName = keyInfo[1]
            local isHold = keyInfo[2]
            
            local activeTime = input.activeKeys[keyName]

            if not activeTime then
                allPressed = false
                break
            end

            if isHold and not (activeTime > holdTime) then
                allPressed = false
                break
            end
        end

        if allPressed then
            for i = 1, #keys do
                input.activeKeys[keys[i][1]] = nil
            end
            binding.callback()
        end
    end
end

function input.createBindingInfo(nativeSettingsPath, keybindLabel, isHoldLabel, keybindDescription, isHoldDescription, id, maxKeys, maxKeysLabel, maxKeysDescription, supportsHold, defaultOptions, savedOptions, callback, saveCallback)
    return {
        nativeSettingsPath = nativeSettingsPath or "",
        keybindLabel = keybindLabel or "",
        isHoldLabel = isHoldLabel or "",
        keybindDescription = keybindDescription or "",
        isHoldDescription = isHoldDescription or "",
        id = id or "",
        maxKeys = maxKeys or 1,
        maxKeysLabel = maxKeysLabel or "",
        maxKeysDescription = maxKeysDescription or "",
        supportsHold = supportsHold or false,
        defaultOptions = defaultOptions or {},
        savedOptions = savedOptions or {},
        callback = callback,
        saveCallback = saveCallback
    }
end

function input.onShutdown()
    if input.callbackID then
        Game.GetCallbackSystem():UnregisterCallback('Input/Key', input.callbackID)
        input.callbackID = nil
    end

    if input.axisCallbackID then
        Game.GetCallbackSystem():UnregisterCallback('Input/Axis', input.axisCallbackID)
        input.axisCallbackID = nil
    end

    if input.inputListener then
        input.inputListener = nil    
    end
end

local function addKeybind(info, index, nativeSettings)
    local numberText = info.maxKeys ~= 1 and " " .. index or ""
    local holdID = info.id .. "_hold_" .. index
    local numID = info.id .. "_" .. index

    if not info.savedOptions[numID] then info.savedOptions[numID] = info.defaultOptions[numID] end
    if not info.savedOptions[holdID] then info.savedOptions[holdID] = info.defaultOptions[holdID] end

    input.bindings[info.id]["keys"][index] = {
        [1] = info.savedOptions[numID],
        [2] = info.savedOptions[holdID]
    }

    if info.supportsHold then
        input.nuiTables[holdID] = nativeSettings.addSwitch(info.nativeSettingsPath, info.isHoldLabel .. numberText, info.isHoldDescription, info.savedOptions[holdID], info.defaultOptions[holdID], function(state)
            input.nuiTables[numID].isHold = state
            nativeSettings.setOption(input.nuiTables[numID], input.nuiTables[numID].value)
            input.bindings[info.id]["keys"][index][2] = state
            info.saveCallback(holdID, state)
        end)
    end

    input.nuiTables[numID] = nativeSettings.addKeyBinding(info.nativeSettingsPath, info.keybindLabel .. numberText, info.keybindDescription, info.savedOptions[numID], info.defaultOptions[numID], info.savedOptions[holdID], function(key)
        input.bindings[info.id]["keys"][index][1] = key
        info.saveCallback(numID, key)
    end)
end

function input.addNativeSettingsBinding(info)
    local nativeSettings = GetMod("nativeSettings")
    
    if not nativeSettings or not nativeSettings.pathExists(info.nativeSettingsPath) then 
        return 
    end

    if not info.savedOptions then info.savedOptions = info.defaultOptions end
    input.bindings[info.id] = {callback = info.callback, keys = {}}

    local maxID = info.id .. "_keys"
    if not info.savedOptions[maxID] then info.savedOptions[maxID] = info.defaultOptions[maxID] end

    if info.maxKeys ~= 1 then
        nativeSettings.addRangeInt(info.nativeSettingsPath, info.maxKeysLabel, info.maxKeysDescription, 1, info.maxKeys, 1, info.savedOptions[maxID], info.defaultOptions[maxID], function(value)
            info.saveCallback(maxID, value)

            for i = value + 1, info.maxKeys do
                if input.nuiTables[info.id .. "_" .. i] then
                    nativeSettings.removeOption(input.nuiTables[info.id .. "_" .. i])
                    input.nuiTables[info.id .. "_" .. i] = nil
                    input.bindings[info.id]["keys"][i] = nil

                    if input.nuiTables[info.id .. "_hold_" .. i] then
                        nativeSettings.removeOption(input.nuiTables[info.id .. "_hold_" .. i])
                        input.nuiTables[info.id .. "_hold_" .. i] = nil
                    end
                end
            end

            for i = 1, value do
                if not input.nuiTables[info.id .. "_" .. i] then
                    addKeybind(info, i, nativeSettings)
                end
            end
        end)
    end
    
    local count = info.savedOptions[maxID] or info.maxKeys or 1

    if type(count) ~= "number" then return end

    for i = 1, count do
        addKeybind(info, i, nativeSettings)
    end
end

return input