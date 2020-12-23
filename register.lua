--[[

No Trespassing Mod

register specialization script
--]]

local modName = g_currentModName
local modDirectory = g_currentModDirectory

source(modDirectory .. "NoTrespassingMod.lua")

local noTrespassingMod = nil

local function isEnabled() return 
    noTrespassingMod ~= nil 
end

function init()
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

    Mission00.load = Utils.prependedFunction(Mission00.load, loadMission)
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)

    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, saveToXMLFile)

    VehicleTypeManager.validateVehicleTypes = Utils.prependedFunction(VehicleTypeManager.validateVehicleTypes, validateVehicleTypes)

--    -- Networking
--    SavegameSettingsEvent.readStream = Utils.appendedFunction(SavegameSettingsEvent.readStream, readStream)
--    SavegameSettingsEvent.writeStream = Utils.appendedFunction(SavegameSettingsEvent.writeStream, writeStream)
--
--    StoreItemUtil.getConfigurationsFromXML = Utils.overwrittenFunction(StoreItemUtil.getConfigurationsFromXML, addConfigurations)

--    VehicleTypeManager.validateVehicleTypes = Utils.prependedFunction(VehicleTypeManager.validateVehicleTypes, validateVehicleTypes)
--    if g_specializationManager:getSpecializationByName("noTrespassing") == nil then
--        local status = g_specializationManager:addSpecialization("noTrespassing", "NoTrespassing", Utils.getFilename("NoTrespassing.lua", modDirectory), true, nil)
--
--        if status then
--            print(string.format("%s: install specialization noTrespassing status=%s", modName, tostring(status)))
--        end
--
--        for vehicleName, vehicleType in pairs(g_vehicleTypeManager.vehicleTypes) do
--            local isDrivable = SpecializationUtil.hasSpecialization(Drivable, vehicleType.specializations)
--            local isEnterable = SpecializationUtil.hasSpecialization(Enterable, vehicleType.specializations)
--            local isMotorized = SpecializationUtil.hasSpecialization(Motorized, vehicleType.specializations)
--            local isSplineVehicle = SpecializationUtil.hasSpecialization(SplineVehicle, vehicleType.specializations)
--                
--            if isDrivable and isEnterable and isMotorized and not isSplineVehicle then
--                g_vehicleTypeManager:addSpecialization(vehicleName, "noTrespassing")
--                print(string.format("%s: spec noTrespassing added to vehicle %s",  modName, vehicleName))
--            end
--        end
--    end
end

function loadMission(mission)
    print(string.format("%s: loadMission()", modName))
    assert(g_noTrespassingMod == nil)

    noTrespassingMod = NoTrespassingMod:new(mission, modDirectory, modName, g_i18n)
    getfenv(0)["g_noTrespassingMod"] = noTrespassingMod
    addModEventListener(noTrespassingMod)
end

function loadedMission(mission, node)
    print(string.format("%s: loadedMission()", modName))

    if mission:getIsServer() then
        if mission.missionInfo.savegameDirectory ~= nil and fileExists(mission.missionInfo.savegameDirectory .. "/noTrespasingDamage.xml") then
            local xmlFile = loadXMLFile("NoTrespassingDamageXML", mission.missionInfo.savegameDirectory .. "/noTrespasingDamage.xml")
            if xmlFile ~= nil then
--                noTrespassingMod:onMissionLoadFromSavegame(xmlFile)
                delete(xmlFile)
            end
        end
    end

    if mission.cancelLoading then return end
--    noTrespassingMod:onMissionLoaded(mission)
end

function unload()
    print(string.format("%s: unload()", modName))

    removeModEventListener(noTrespassingMod)

    noTrespassingMod:delete()
    noTrespassingMod = nil -- allow garbage collection
    getfenv(0)["g_noTrespassingMod"] = nil
end

function saveToXMLFile(missionInfo)
    print(string.format("%s: saveToXMLFile()", modName))

    if missionInfo.isValid then
        local xmlFile = createXMLFile("NoTrespassingXML", missionInfo.savegameDirectory .. "/noTrespasing.xml", "noTrespassing")
        if xmlFile ~= nil then
            -- noTrespassingMod:onMissionSaveToSavegame(xmlFile) -- fil data from noTrespassingMod class instance
            saveXMLFile(xmlFile) -- perform write to hard drive
            delete(xmlFile)
        end
    end
end

function readStream(e, streamId, connection)
    print(string.format("%s: readStream()", modName))
end

function writeStream(e, streamId, connection) 
    print(string.format("%s: writeStream()", modName))
end

-- hooks --
function validateVehicleTypes(vehicleTypeManager)
    print(string.format("%s: validateVehicleTypes()", modName))

    NoTrespassingMod.installSpecializations(g_vehicleTypeManager, g_specializationManager, modDirectory, modName)
end

-- init mod --
init()

-------------------------------------------------------------------------------
--- Extra functionality to abstract away some internal details
-------------------------------------------------------------------------------

function Vehicle:getNoTrespassingSpec()
    local spec = self["spec_" .. modName .. ".noTrespassing"]
    if spec == nil then
        print(string.format("%s: could not find specialization for vehicle!", modName))
    end

    return spec
end