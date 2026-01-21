local isDragging = false
local dragAxis = nil
local dragStartPos = nil
local dragStartOffset = nil
local dragStartRotation = nil
local hoveredAxis = nil

local function GetMouseWorldPosition()
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    
    local camForward = vector3(
        -math.sin(math.rad(camRot.z)) * math.cos(math.rad(camRot.x)),
        math.cos(math.rad(camRot.z)) * math.cos(math.rad(camRot.x)),
        math.sin(math.rad(camRot.x))
    )
    
    local rayEnd = camCoords + (camForward * 100.0)
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, rayEnd.x, rayEnd.y, rayEnd.z, -1, PlayerPedId(), 0)
    local _, hit, hitCoords = GetShapeTestResult(ray)
    
    return hit and hitCoords or rayEnd
end

local function WorldToScreen(worldPos)
    return GetScreenCoordFromWorldCoord(worldPos.x, worldPos.y, worldPos.z)
end

local function DrawGizmoArrow(pos, direction, color, size, isHovered, isActive)
    local endPos = pos + (direction * size)
    local drawColor = { r = color.r, g = color.g, b = color.b, a = color.a }
    
    if isActive then
        drawColor.a = 255
        drawColor.r = math.min(255, drawColor.r + 50)
        drawColor.g = math.min(255, drawColor.g + 50)
        drawColor.b = math.min(255, drawColor.b + 50)
    elseif isHovered then
        drawColor.a = 255
    end
    
    local thickness = (isHovered or isActive) and 3 or 1
    for i = 1, thickness do
        DrawLine(pos.x, pos.y, pos.z, endPos.x, endPos.y, endPos.z, 
            drawColor.r, drawColor.g, drawColor.b, drawColor.a)
    end
    
    local headSize = (isHovered or isActive) and 0.04 or 0.025
    DrawMarker(2, endPos.x, endPos.y, endPos.z, 
        direction.x, direction.y, direction.z, 0, 0, 0,
        headSize, headSize, headSize * 2,
        drawColor.r, drawColor.g, drawColor.b, drawColor.a,
        false, false, 2, false, nil, nil, false)
    
    return endPos
end

local function DrawRotationRing(pos, axis, color, size, isHovered, isActive)
    local segments = 36
    local angleStep = 360.0 / segments
    
    local drawColor = { r = color.r, g = color.g, b = color.b, a = color.a }
    
    if isActive then
        drawColor.a = 255
        drawColor.r = math.min(255, drawColor.r + 50)
        drawColor.g = math.min(255, drawColor.g + 50)
        drawColor.b = math.min(255, drawColor.b + 50)
    elseif isHovered then
        drawColor.a = 255
    end
    
    local thickness = (isHovered or isActive) and 2 or 1
    
    for i = 0, segments - 1 do
        local a1 = math.rad(i * angleStep)
        local a2 = math.rad((i + 1) * angleStep)
        local p1, p2
        
        if axis == "x" then
            p1 = pos + vector3(0, math.cos(a1) * size, math.sin(a1) * size)
            p2 = pos + vector3(0, math.cos(a2) * size, math.sin(a2) * size)
        elseif axis == "y" then
            p1 = pos + vector3(math.cos(a1) * size, 0, math.sin(a1) * size)
            p2 = pos + vector3(math.cos(a2) * size, 0, math.sin(a2) * size)
        else
            p1 = pos + vector3(math.cos(a1) * size, math.sin(a1) * size, 0)
            p2 = pos + vector3(math.cos(a2) * size, math.sin(a2) * size, 0)
        end
        
        for j = 1, thickness do
            DrawLine(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z,
                drawColor.r, drawColor.g, drawColor.b, drawColor.a)
        end
    end
end

function DrawGizmo(propHandle, mode)
    if not propHandle or not DoesEntityExist(propHandle) then return end
    
    local pos = GetEntityCoords(propHandle)
    local size = Config.Gizmo.Size
    local colors = Config.Gizmo.AxisColors
    
    if mode == "translate" then
        DrawGizmoArrow(pos, vector3(1, 0, 0), colors.X, size, hoveredAxis == "x", isDragging and dragAxis == "x")
        DrawGizmoArrow(pos, vector3(0, 1, 0), colors.Y, size, hoveredAxis == "y", isDragging and dragAxis == "y")
        DrawGizmoArrow(pos, vector3(0, 0, 1), colors.Z, size, hoveredAxis == "z", isDragging and dragAxis == "z")
    else
        DrawRotationRing(pos, "x", colors.X, size * 0.8, hoveredAxis == "x", isDragging and dragAxis == "x")
        DrawRotationRing(pos, "y", colors.Y, size * 0.8, hoveredAxis == "y", isDragging and dragAxis == "y")
        DrawRotationRing(pos, "z", colors.Z, size * 0.8, hoveredAxis == "z", isDragging and dragAxis == "z")
    end
    
    DrawMarker(28, pos.x, pos.y, pos.z, 0, 0, 0, 0, 0, 0,
        0.04, 0.04, 0.04, 255, 255, 255, 200, false, false, 2, false, nil, nil, false)
end

function CheckAxisHover(propPos, mode)
    if isDragging then return dragAxis end
    
    local mouseX, mouseY = GetNuiCursorPosition()
    local screenW, screenH = GetActiveScreenResolution()
    local normX, normY = mouseX / screenW, mouseY / screenH
    
    local size = Config.Gizmo.Size
    local hitThreshold = 0.0
    local closestAxis, closestDist = nil, hitThreshold
    
    if mode == "translate" then
        local axes = {
            { name = "x", dir = vector3(1, 0, 0) },
            { name = "y", dir = vector3(0, 1, 0) },
            { name = "z", dir = vector3(0, 0, 1) },
        }
        
        for _, axis in ipairs(axes) do
            for t = 0.1, 1.0, 0.15 do
                local axisPoint = propPos + (axis.dir * size * t)
                local onScreen, screenX, screenY = WorldToScreen(axisPoint)
                if onScreen then
                    local dist = math.sqrt((normX - screenX)^2 + (normY - screenY)^2)
                    if dist < closestDist then
                        closestDist, closestAxis = dist, axis.name
                    end
                end
            end
        end
    else
        local ringSize = size * 0.8
        local segments = 24
        
        for i = 0, segments - 1 do
            local angle = math.rad((i / segments) * 360)
            local cosA, sinA = math.cos(angle), math.sin(angle)
            
            local pointX = propPos + vector3(0, cosA * ringSize, sinA * ringSize)
            local onScreen, screenX, screenY = WorldToScreen(pointX)
            if onScreen then
                local dist = math.sqrt((normX - screenX)^2 + (normY - screenY)^2)
                if dist < closestDist then
                    closestDist, closestAxis = dist, "x"
                end
            end
            
            local pointY = propPos + vector3(cosA * ringSize, 0, sinA * ringSize)
            onScreen, screenX, screenY = WorldToScreen(pointY)
            if onScreen then
                local dist = math.sqrt((normX - screenX)^2 + (normY - screenY)^2)
                if dist < closestDist then
                    closestDist, closestAxis = dist, "y"
                end
            end
            
            local pointZ = propPos + vector3(cosA * ringSize, sinA * ringSize, 0)
            onScreen, screenX, screenY = WorldToScreen(pointZ)
            if onScreen then
                local dist = math.sqrt((normX - screenX)^2 + (normY - screenY)^2)
                if dist < closestDist then
                    closestDist, closestAxis = dist, "z"
                end
            end
        end
    end
    
    return closestAxis
end

function StartDrag(axis, propData)
    isDragging = true
    dragAxis = axis
    dragStartPos = GetNuiCursorPosition()
    dragStartOffset = propData.offset
    dragStartRotation = propData.rotation
end

function StopDrag()
    isDragging = false
    dragAxis = nil
    dragStartPos = nil
    dragStartOffset = nil
    dragStartRotation = nil
end

function UpdateDrag(propData, mode)
    if not isDragging or not dragAxis then return nil, nil end
    
    local currentX, currentY = GetNuiCursorPosition()
    local deltaX = (currentX - dragStartPos) / 500
    local deltaY = (dragStartPos - currentY) / 500
    
    local newOffset = dragStartOffset
    local newRotation = dragStartRotation
    local moveStep = Config.MoveStep * 500
    local rotStep = Config.RotateStep * 100
    
    if mode == "translate" then
        if dragAxis == "x" then
            newOffset = vector3(dragStartOffset.x + (deltaX * moveStep), dragStartOffset.y, dragStartOffset.z)
        elseif dragAxis == "y" then
            newOffset = vector3(dragStartOffset.x, dragStartOffset.y + (deltaX * moveStep), dragStartOffset.z)
        elseif dragAxis == "z" then
            newOffset = vector3(dragStartOffset.x, dragStartOffset.y, dragStartOffset.z + (deltaY * moveStep))
        end
    else
        if dragAxis == "x" then
            newRotation = vector3(dragStartRotation.x + (deltaY * rotStep), dragStartRotation.y, dragStartRotation.z)
        elseif dragAxis == "y" then
            newRotation = vector3(dragStartRotation.x, dragStartRotation.y + (deltaX * rotStep), dragStartRotation.z)
        elseif dragAxis == "z" then
            newRotation = vector3(dragStartRotation.x, dragStartRotation.y, dragStartRotation.z + (deltaX * rotStep))
        end
    end
    
    return newOffset, newRotation
end

function SetHoveredAxis(axis) hoveredAxis = axis end
function GetHoveredAxis() return hoveredAxis end
function IsDragging() return isDragging end
function GetDragAxis() return dragAxis end
