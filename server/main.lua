local Fetch, Phone = nil, nil

RegisterNetEvent("srp-vehprop:Server:SaveExport", function(exportData)
    local src = source
    
    if not exportData or not exportData.props then return end
    
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local vehicleName = exportData.vehicle or "unknown"
    local filename = ("%s_%s.json"):format(vehicleName, timestamp)
    
    local resourcePath = GetResourcePath(GetCurrentResourceName())
    local exportPath = resourcePath .. "/" .. Config.ExportPath
    
    os.execute('mkdir "' .. exportPath .. '" 2>nul')
    
    local file = io.open(exportPath .. filename, "w")
    if file then
        file:write(json.encode(exportData, { indent = true }))
        file:close()
        print(("[srp-vehprop] Export saved: %s"):format(filename))
    else
        print(("[srp-vehprop] Failed to save: %s"):format(filename))
    end
end)

-- Framework Integration
AddEventHandler("Core:Shared:Ready", function()
    exports["mythic-base"]:RequestDependencies("VehProp", {
        "Fetch",
        "Phone",
    }, function(error)
        if #error > 0 then return end
        
        Fetch = exports["mythic-base"]:FetchComponent("Fetch")
        Phone = exports["mythic-base"]:FetchComponent("Phone")
    end)
end)
