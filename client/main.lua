local Fetch, Callbacks, Notification = nil, nil, nil

local isMenuOpen = false
local currentVehicle = nil
local attachedProps = {}
local selectedProp = nil
local gizmoMode = "translate"
local gizmoThread = nil

local isFreecamActive = false
local freecamCam = nil
local freecamPos = nil
local freecamRot = nil
local freecamKeys = { w = false, a = false, s = false, d = false, q = false, e = false }

local nuiDragAxis = nil
local nuiDragMode = nil
local nuiDragStartOffset = nil
local nuiDragStartRotation = nil

local function LoadModel(model)
    local hash = type(model) == "string" and GetHashKey(model) or model
    if not IsModelValid(hash) then return false, nil end
    
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 5000 do
        Wait(10)
        timeout = timeout + 10
    end
    
    return HasModelLoaded(hash), hash
end

local function GetVehicleBoneIndex(vehicle)
    local boneIndex = GetEntityBoneIndexByName(vehicle, "chassis")
    if boneIndex == -1 then boneIndex = GetEntityBoneIndexByName(vehicle, "bodyshell") end
    if boneIndex == -1 then boneIndex = 0 end
    return boneIndex
end

local function SendPropsToUI()
    local propList = {}
    for handle, data in pairs(attachedProps) do
        propList[#propList + 1] = {
            handle = handle,
            model = data.model,
            label = data.label,
            offset = data.offset,
            rotation = data.rotation,
        }
    end
    SendNUIMessage({ action = "updateProps", props = propList, selectedProp = selectedProp })
end

local function AttachProp(model, label)
    if not currentVehicle or not DoesEntityExist(currentVehicle) then
        Notification:Error("You are not in a vehicle!", 3000)
        return
    end
    
    local propCount = 0
    for _ in pairs(attachedProps) do propCount = propCount + 1 end
    if propCount >= Config.MaxPropsPerVehicle then
        Notification:Error("Maximum prop limit reached!", 3000)
        return
    end
    
    local success, hash = LoadModel(model)
    if not success then
        Notification:Error("Invalid model: " .. model, 3000)
        return
    end
    
    local vehCoords = GetEntityCoords(currentVehicle)
    local prop = CreateObject(hash, vehCoords.x, vehCoords.y, vehCoords.z + 1.0, true, false, false)
    
    if not DoesEntityExist(prop) then
        Notification:Error("Error creating prop!", 3000)
        return
    end
    
    local offset = vector3(0.0, 0.0, 1.0)
    local rotation = vector3(0.0, 0.0, 0.0)
    local boneIndex = GetVehicleBoneIndex(currentVehicle)
    
    AttachEntityToEntity(prop, currentVehicle, boneIndex, 
        offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z,
        false, false, false, false, 2, true)
    SetEntityCollision(prop, false, false)
    
    attachedProps[prop] = {
        model = model,
        label = label,
        offset = offset,
        rotation = rotation,
        boneIndex = boneIndex,
    }
    selectedProp = prop
    
    SendPropsToUI()
    Notification:Success("Prop added: " .. label, 2000)
end

local function RemoveProp(propHandle)
    if not attachedProps[propHandle] then return end
    
    if DoesEntityExist(propHandle) then
        DetachEntity(propHandle, true, true)
        DeleteEntity(propHandle)
    end
    attachedProps[propHandle] = nil
    
    if selectedProp == propHandle then selectedProp = nil end
    
    SendPropsToUI()
    Notification:Info("Prop deleted!", 2000)
end

local function SelectProp(propHandle)
    if attachedProps[propHandle] then
        selectedProp = propHandle
        SendPropsToUI()
    end
end

local function UpdatePropPosition(propHandle, offset, rotation)
    local data = attachedProps[propHandle]
    if not data or not DoesEntityExist(propHandle) then return end
    
    data.offset = offset
    data.rotation = rotation
    
    DetachEntity(propHandle, true, true)
    AttachEntityToEntity(propHandle, currentVehicle, data.boneIndex,
        offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z,
        false, false, false, false, 2, true)
    
    attachedProps[propHandle] = data
    SendPropsToUI()
end

local function ClearAllProps()
    for handle in pairs(attachedProps) do
        if DoesEntityExist(handle) then
            DetachEntity(handle, true, true)
            DeleteEntity(handle)
        end
    end
    attachedProps = {}
    selectedProp = nil
    SendPropsToUI()
end

local function GenerateExportData()
    if not currentVehicle or not DoesEntityExist(currentVehicle) then return nil end
    
    local vehicleModel = GetEntityModel(currentVehicle)
    local propsData = {}
    
    for _, data in pairs(attachedProps) do
        propsData[#propsData + 1] = {
            model = data.model,
            label = data.label,
            offset = { x = data.offset.x, y = data.offset.y, z = data.offset.z },
            rotation = { x = data.rotation.x, y = data.rotation.y, z = data.rotation.z },
        }
    end
    
    return {
        vehicle = GetDisplayNameFromVehicleModel(vehicleModel),
        vehicleHash = vehicleModel,
        props = propsData,
    }
end

local function SaveExport()
    local exportData = GenerateExportData()
    if not exportData then
        Notification:Error("You are not in a vehicle!", 3000)
        return
    end
    if #exportData.props == 0 then
        Notification:Error("No props to export!", 3000)
        return
    end
    
    TriggerServerEvent("srp-vehprop:Server:SaveExport", exportData)
    Notification:Success("Export saved! Check the exports/ folder", 4000)
end

local function OpenMenu()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if not vehicle or vehicle == 0 then
        Notification:Error("You must be in a vehicle!", 3000)
        return
    end
    
    currentVehicle = vehicle
    isMenuOpen = true
    
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "open", gizmoMode = gizmoMode })
    SendPropsToUI()
    StartGizmoThread()
end

local function CloseMenu()
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
    
    if freecamCam then
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(freecamCam, false)
        freecamCam = nil
    end
    isFreecamActive = false
    freecamPos = nil
    freecamRot = nil
    
    StopGizmoThread()
end

local function StartFreecam()
    if isFreecamActive then return end
    
    isFreecamActive = true
    for k in pairs(freecamKeys) do freecamKeys[k] = false end
    
    SetNuiFocus(true, false)
    
    if not freecamCam then
        freecamPos = GetGameplayCamCoord()
        freecamRot = GetGameplayCamRot(2)
        freecamCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(freecamCam, freecamPos.x, freecamPos.y, freecamPos.z)
        SetCamRot(freecamCam, freecamRot.x, freecamRot.y, freecamRot.z, 2)
        RenderScriptCams(true, false, 0, true, true)
    end
    
    SendNUIMessage({ action = "showFreecamHint", active = true })
end

local function StopFreecam()
    if not isFreecamActive then return end
    
    isFreecamActive = false
    SetNuiFocus(true, true)
    
    SendNUIMessage({ action = "showFreecamHint", active = false })
end

local function UpdateFreecam()
    if not freecamCam then return end
    
    local moveSpeed = Config.Freecam.MoveSpeed
    local rotSpeed = Config.Freecam.RotateSpeed
    
    local mouseX = GetDisabledControlNormal(0, 1) * rotSpeed
    local mouseY = GetDisabledControlNormal(0, 2) * rotSpeed
    
    freecamRot = vector3(
        math.max(-89.0, math.min(89.0, freecamRot.x - mouseY)),
        freecamRot.y,
        freecamRot.z - mouseX
    )
    
    local rotRad = math.rad(freecamRot.z)
    local forward = vector3(-math.sin(rotRad), math.cos(rotRad), 0.0)
    local right = vector3(math.cos(rotRad), math.sin(rotRad), 0.0)
    
    if freecamKeys.w then freecamPos = freecamPos + (forward * moveSpeed) end
    if freecamKeys.s then freecamPos = freecamPos - (forward * moveSpeed) end
    if freecamKeys.a then freecamPos = freecamPos - (right * moveSpeed) end
    if freecamKeys.d then freecamPos = freecamPos + (right * moveSpeed) end
    if freecamKeys.q then freecamPos = freecamPos - vector3(0, 0, moveSpeed) end
    if freecamKeys.e then freecamPos = freecamPos + vector3(0, 0, moveSpeed) end
    
    SetCamCoord(freecamCam, freecamPos.x, freecamPos.y, freecamPos.z)
    SetCamRot(freecamCam, freecamRot.x, freecamRot.y, freecamRot.z, 2)
end

function StartGizmoThread()
    if gizmoThread then return end
    
    gizmoThread = Citizen.CreateThread(function()
        while isMenuOpen do
            Citizen.Wait(0)
            
            if isFreecamActive then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 38, true)
                UpdateFreecam()
            end
            
            if selectedProp and DoesEntityExist(selectedProp) then
                DrawGizmo(selectedProp, gizmoMode)
            end
        end
        
        if isFreecamActive then StopFreecam() end
        gizmoThread = nil
    end)
end

function StopGizmoThread()
    if IsDragging() then StopDrag() end
    gizmoThread = nil
end

RegisterNUICallback("close", function(_, cb)
    CloseMenu()
    cb("ok")
end)

RegisterNUICallback("addProp", function(data, cb)
    AttachProp(data.model, data.label)
    cb("ok")
end)

RegisterNUICallback("removeProp", function(data, cb)
    RemoveProp(data.handle)
    cb("ok")
end)

RegisterNUICallback("selectProp", function(data, cb)
    SelectProp(data.handle)
    cb("ok")
end)

RegisterNUICallback("clearAll", function(_, cb)
    ClearAllProps()
    Notification:Info("All props have been deleted!", 2000)
    cb("ok")
end)

RegisterNUICallback("saveExport", function(_, cb)
    SaveExport()
    cb("ok")
end)

RegisterNUICallback("setGizmoMode", function(data, cb)
    gizmoMode = data.mode
    cb("ok")
end)

RegisterNUICallback("moveProp", function(data, cb)
    if not selectedProp or not attachedProps[selectedProp] then
        cb("ok")
        return
    end
    
    local propData = attachedProps[selectedProp]
    local step, rotStep = Config.MoveStep, Config.RotateStep
    local newOffset, newRotation = propData.offset, propData.rotation
    
    if data.type == "translate" then
        if data.axis == "x" then
            newOffset = vector3(newOffset.x + (step * data.direction), newOffset.y, newOffset.z)
        elseif data.axis == "y" then
            newOffset = vector3(newOffset.x, newOffset.y + (step * data.direction), newOffset.z)
        elseif data.axis == "z" then
            newOffset = vector3(newOffset.x, newOffset.y, newOffset.z + (step * data.direction))
        end
    else
        if data.axis == "x" then
            newRotation = vector3(newRotation.x + (rotStep * data.direction), newRotation.y, newRotation.z)
        elseif data.axis == "y" then
            newRotation = vector3(newRotation.x, newRotation.y + (rotStep * data.direction), newRotation.z)
        elseif data.axis == "z" then
            newRotation = vector3(newRotation.x, newRotation.y, newRotation.z + (rotStep * data.direction))
        end
    end
    
    UpdatePropPosition(selectedProp, newOffset, newRotation)
    cb("ok")
end)

RegisterNUICallback("resetAxis", function(data, cb)
    if not selectedProp or not attachedProps[selectedProp] then
        cb("ok")
        return
    end
    
    local propData = attachedProps[selectedProp]
    local newOffset, newRotation = propData.offset, propData.rotation
    
    if data.type == "translate" then
        if data.axis == "x" then newOffset = vector3(0, newOffset.y, newOffset.z)
        elseif data.axis == "y" then newOffset = vector3(newOffset.x, 0, newOffset.z)
        elseif data.axis == "z" then newOffset = vector3(newOffset.x, newOffset.y, 0) end
    else
        if data.axis == "x" then newRotation = vector3(0, newRotation.y, newRotation.z)
        elseif data.axis == "y" then newRotation = vector3(newRotation.x, 0, newRotation.z)
        elseif data.axis == "z" then newRotation = vector3(newRotation.x, newRotation.y, 0) end
    end
    
    UpdatePropPosition(selectedProp, newOffset, newRotation)
    cb("ok")
end)

RegisterNUICallback("gizmoDragStart", function(data, cb)
    if not selectedProp or not attachedProps[selectedProp] then
        cb("ok")
        return
    end
    
    local propData = attachedProps[selectedProp]
    nuiDragAxis = data.axis
    nuiDragMode = data.mode
    nuiDragStartOffset = propData.offset
    nuiDragStartRotation = propData.rotation
    cb("ok")
end)

RegisterNUICallback("gizmoDrag", function(data, cb)
    if not selectedProp or not attachedProps[selectedProp] or not nuiDragAxis then
        cb("ok")
        return
    end
    
    local sensitivity, rotSensitivity = 0.001, 0.1
    local newOffset, newRotation = nuiDragStartOffset, nuiDragStartRotation
    
    if nuiDragMode == "translate" then
        local deltaX = data.deltaX * sensitivity
        local deltaY = -data.deltaY * sensitivity
        if nuiDragAxis == "x" then
            newOffset = vector3(nuiDragStartOffset.x + deltaX, nuiDragStartOffset.y, nuiDragStartOffset.z)
        elseif nuiDragAxis == "y" then
            newOffset = vector3(nuiDragStartOffset.x, nuiDragStartOffset.y - deltaX, nuiDragStartOffset.z)
        elseif nuiDragAxis == "z" then
            newOffset = vector3(nuiDragStartOffset.x, nuiDragStartOffset.y, nuiDragStartOffset.z + deltaY)
        end
    else
        local delta = data.deltaX * rotSensitivity
        if nuiDragAxis == "x" then
            newRotation = vector3(nuiDragStartRotation.x + delta, nuiDragStartRotation.y, nuiDragStartRotation.z)
        elseif nuiDragAxis == "y" then
            newRotation = vector3(nuiDragStartRotation.x, nuiDragStartRotation.y + delta, nuiDragStartRotation.z)
        elseif nuiDragAxis == "z" then
            newRotation = vector3(nuiDragStartRotation.x, nuiDragStartRotation.y, nuiDragStartRotation.z + delta)
        end
    end
    
    UpdatePropPosition(selectedProp, newOffset, newRotation)
    SendNUIMessage({
        action = "updatePropPosition",
        handle = selectedProp,
        offset = { x = newOffset.x, y = newOffset.y, z = newOffset.z },
        rotation = { x = newRotation.x, y = newRotation.y, z = newRotation.z },
    })
    cb("ok")
end)

RegisterNUICallback("gizmoDragEnd", function(_, cb)
    nuiDragAxis, nuiDragMode, nuiDragStartOffset, nuiDragStartRotation = nil, nil, nil, nil
    SendNUIMessage({ action = "stop3DDrag" })
    cb("ok")
end)

RegisterNUICallback("checkGizmoHover", function(data, cb)
    if not selectedProp or not attachedProps[selectedProp] then
        cb("ok")
        return
    end
    
    local propPos = GetEntityCoords(selectedProp)
    local hovered = CheckAxisHover(propPos, gizmoMode)
    SetHoveredAxis(hovered)
    
    SendNUIMessage({ action = "setHoveredAxis", axis = hovered })
    cb("ok")
end)

RegisterNUICallback("checkGizmoClick", function(data, cb)
    if not selectedProp or not attachedProps[selectedProp] then
        cb("ok")
        return
    end
    
    local propPos = GetEntityCoords(selectedProp)
    local hovered = CheckAxisHover(propPos, gizmoMode)
    
    if hovered then
        local propData = attachedProps[selectedProp]
        nuiDragAxis = hovered
        nuiDragMode = gizmoMode
        nuiDragStartOffset = propData.offset
        nuiDragStartRotation = propData.rotation
        
        SendNUIMessage({ 
            action = "start3DDrag", 
            axis = hovered,
            mouseX = data.mouseX,
            mouseY = data.mouseY
        })
    end
    
    cb("ok")
end)

RegisterNUICallback("toggleFreecam", function(_, cb)
    if isFreecamActive then
        StopFreecam()
    else
        StartFreecam()
    end
    cb("ok")
end)

RegisterNUICallback("freecamKey", function(data, cb)
    if data.key and freecamKeys[data.key] ~= nil then
        freecamKeys[data.key] = data.pressed
    end
    cb("ok")
end)

RegisterCommand("vehprop", function()
    if isMenuOpen then CloseMenu() else OpenMenu() end
end, false)

RegisterKeyMapping("vehprop", "Open Vehicle Props Menu", "keyboard", Config.OpenKey)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ClearAllProps()
    CloseMenu()
end)

AddEventHandler("Core:Shared:Ready", function()
    exports["mythic-base"]:RequestDependencies("VehProp", {
        "Fetch",
        "Callbacks",
        "Notification",
    }, function(error)
        if #error > 0 then return end
        
        Fetch = exports["mythic-base"]:FetchComponent("Fetch")
        Callbacks = exports["mythic-base"]:FetchComponent("Callbacks")
        Notification = exports["mythic-base"]:FetchComponent("Notification")
        
    end)
end)
