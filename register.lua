--[[

No Trespassing Mod

register specialization script
--]]

local noTrespassing

local function isEnabled() return 
    noTrespassing ~= nil 
end

function init()
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

    Mission00.load = Utils.prependedFunction(Mission00.load, loadMission)
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)

    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, saveToXMLFile)
--
--    -- Networking
--    SavegameSettingsEvent.readStream = Utils.appendedFunction(SavegameSettingsEvent.readStream, readStream)
--    SavegameSettingsEvent.writeStream = Utils.appendedFunction(SavegameSettingsEvent.writeStream, writeStream)
--
--    VehicleTypeManager.validateVehicleTypes = Utils.prependedFunction(VehicleTypeManager.validateVehicleTypes, validateVehicleTypes)
--    StoreItemUtil.getConfigurationsFromXML = Utils.overwrittenFunction(StoreItemUtil.getConfigurationsFromXML, addGPSConfigurationUtil)
end

function loadMission(mission)
    assert(g_noTrespassing == nil)

    noTrespassing = NoTrespassing:new(mission, g_currentModDirectory, g_currentModName, g_i18n)
    getfenv(0)["g_noTrespassing"] = noTrespassing
    addModEventListener(noTrespassing)
end

function loadedMission(mission, node)
    if not isEnabled() then return end

    if mission:getIsServer() then
        if mission.missionInfo.savegameDirectory ~= nil and fileExists(mission.missionInfo.savegameDirectory .. "/noTrespasingDamage.xml") then
            local xmlFile = loadXMLFile("NoTrespassingDamageXML", mission.missionInfo.savegameDirectory .. "/noTrespasingDamage.xml")
            if xmlFile ~= nil then
--                noTrespassing:onMissionLoadFromSavegame(xmlFile)
                delete(xmlFile)
            end
        end
    end

    if mission.cancelLoading then return end

--    noTrespassing:onMissionLoaded(mission)
end

function unload()
    if not isEnabled() then return end

    removeModEventListener(noTrespassing)

    noTrespassing:delete()
    noTrespassing = nil -- allow garbage collection
    getfenv(0)["g_noTrespassing"] = nil
end

function saveToXMLFile(missionInfo)
    if not isEnabled() then return end

    if missionInfo.isValid then
        local xmlFile = createXMLFile("NoTrespassingDamageXML", missionInfo.savegameDirectory .. "/noTrespasingDamage.xml", "noTrespassingDamage")
        if xmlFile ~= nil then
            -- noTrespassing:onMissionSaveToSavegame(xmlFile) -- fil data from noTrespassing spec instance
            saveXMLFile(xmlFile) -- perform write to hard drive
            delete(xmlFile)
        end
    end
end

function readStream(e, streamId, connection) end
function writeStream(e, streamId, connection) end

if g_specializationManager:getSpecializationByName("noTrespassing") == nil then
    local status = g_specializationManager:addSpecialization("noTrespassing", "NoTrespassing", Utils.getFilename("NoTrespassing.lua", g_currentModDirectory), true, nil)

    if status then
        print(string.format("%s: install specialization noTrespassing status=%s", g_currentModName), tostring(status))
    end

    for vehicleName, vehicleType in pairs(g_vehicleTypeManager.vehicleTypes) do
        local isDrivable = SpecializationUtil.hasSpecialization(Drivable, vehicleType.specializations)
        local isEnterable = SpecializationUtil.hasSpecialization(Enterable, vehicleType.specializations)
        local isMotorized = SpecializationUtil.hasSpecialization(Motorized, vehicleType.specializations)
        local isSplineVehicle = SpecializationUtil.hasSpecialization(SplineVehicle, vehicleType.specializations)
            
        if isDrivable and isEnterable and isMotorized and not isSplineVehicle then
            g_vehicleTypeManager:addSpecialization(vehicleName, "noTrespassing")
            print(string.format("%s: spec noTrespassing added to vehicle %s",  g_currentModName, vehicleName))
        end
    end
end

init()
