--[[

loader.lua

This is file with NoTrespassing mod initialization functions.

Author: bodzio528
Version: 0.1
Created: 2020-12-22

Changelog:
2020-12-22 initial version
2020-12-28 merge with register function file
2021-01-30 rewrite loader function, cleanup the code
]]

local modName = g_currentModName
local modDirectory = g_currentModDirectory

local function onStartMission(mission)

end

local function onFinalizeVehicleTypes(vehicleTypesManager)

end

function delete()
    getfenv(0)["g_noTrespassingMod"] = nil
end

local function init()
    if g_noTrespassingMod ~= nil then
        return
    end
    
    getfenv(0)["g_noTrespassingMod"] = {}
    --addModEventListener(noTrespassingMod)

    -- merge mod translations --
    local i18nRefGlobal = getfenv(0).g_i18n.texts
    for key, text in pairs(i18n.texts) do
        i18nRefGlobal[key] = text
    end
    
    --noTrespassingMod = NoTrespassingMod:new(mission, modDirectory, modName, g_i18n)
end

init()

------------------------------------------------------------------------------------------------------------------------------------------

function NoTrespassingMod.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    specializationManager:addSpecialization("noTrespassing", "NoTrespassing", Utils.getFilename("NoTrespassing.lua", modDirectory), nil)

    for vehicleName, vehicleType in pairs(vehicleTypeManager:getVehicleTypes()) do
        local isDrivable = SpecializationUtil.hasSpecialization(Drivable, vehicleType.specializations)
        local isEnterable = SpecializationUtil.hasSpecialization(Enterable, vehicleType.specializations)
        local isMotorized = SpecializationUtil.hasSpecialization(Motorized, vehicleType.specializations)
        local isSplineVehicle = SpecializationUtil.hasSpecialization(SplineVehicle, vehicleType.specializations)
            
        if isDrivable and isEnterable and isMotorized and not isSplineVehicle then
            vehicleTypeManager:addSpecialization(vehicleName, modName .. ".noTrespassing")
        end
    end
end

-------------------------------------------------------------------------------
-- register NoTrespassing as available mod
-------------------------------------------------------------------------------
function init()
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

    Mission00.load = Utils.prependedFunction(Mission00.load, loadMission)
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)

    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, saveToXMLFile)

    VehicleTypeManager.validateVehicleTypes = Utils.prependedFunction(VehicleTypeManager.validateVehicleTypes, validateVehicleTypes)

    loadCropsData()

--    -- Networking
--    SavegameSettingsEvent.readStream = Utils.appendedFunction(SavegameSettingsEvent.readStream, readStream)
--    SavegameSettingsEvent.writeStream = Utils.appendedFunction(SavegameSettingsEvent.writeStream, writeStream)
end

function loadMission(mission)
    assert(g_noTrespassingMod == nil)

    -- merge mod translations --
    local i18nRefGlobal = getfenv(0).g_i18n.texts
    for key, text in pairs(i18n.texts) do
        i18nRefGlobal[key] = text
    end

    noTrespassingMod = NoTrespassingMod:new(mission, modDirectory, modName, g_i18n)
    getfenv(0)["g_noTrespassingMod"] = noTrespassingMod
    addModEventListener(noTrespassingMod)
end

function loadedMission(mission, node)
    if mission:getIsServer() then
        if mission.missionInfo.savegameDirectory ~= nil and fileExists(mission.missionInfo.savegameDirectory .. "/noTrespasing.xml") then
            local xmlFile = loadXMLFile("NoTrespassingXML", mission.missionInfo.savegameDirectory .. "/noTrespasing.xml")
            if xmlFile ~= nil then
                noTrespassingMod:onMissionLoadFromSavegame(xmlFile)
                delete(xmlFile)
            end
        end
    end

    if mission.cancelLoading then return end
--    noTrespassingMod:onMissionLoaded(mission)
end


-- hooks --
function validateVehicleTypes(vehicleTypeManager)
    NoTrespassingMod.installSpecializations(g_vehicleTypeManager, g_specializationManager, modDirectory, modName)
end

-- init mod --
init()

--------------------------------------------
--        LOAD XROPS DATA FROM XML        --
--------------------------------------------

function loadCropsData()
    local path = Utils.getFilename("data/noTrespassing.xml", modDirectory)
    if fileExists(path) then
        local xmlFile = loadXMLFile("noTrespassing", path)
        local cropsData = loadCropsDataFromXml(xmlFile)
        delete(xmlFile)
    end

    return cropsData
end

function loadCropsDataFromXml(xmlFile)
    local data = {}

    data.difficulty = { 0.75, 1.0, 1.5 } -- sane defaults if xml is corrupted
    local difficultyKey = "noTrespassing.difficulty"
    if hasXMLProperty(xmlFile, difficultyKey) then
        data.difficulty = { 
            getXMLFloat(xmlFile, difficultyKey .. "#easy"), 
            getXMLFloat(xmlFile, difficultyKey .. "#normal"), 
            getXMLFloat(xmlFile, difficultyKey .. "#hard")
        }
    end
    
    data.ground = 0.1 -- sane defaults if xml is corrupted
    local groundKey = "noTrespassing.ground"
    if hasXMLProperty(xmlFile, groundKey) then
        data.ground = getXMLFloat(xmlFile, groundKey .. "#base")
    end
        
    data.crops = {} -- sane defaults if xml is corrupted
    data.crops["BARLEY"] = {
        base=1.0,
        young=0.4,
        mature=1.0,
        harvested=0.1
    }

    local categories = {} -- no need to store categories, use and discard for faster lookup
    local j = 0
    while true do
        local categoryKey = string.format("noTrespassing.categories.category(%d)", j)
        if not hasXMLProperty(xmlFile, categoryKey) then 
            break 
        end

        local categoryName = getXmlString(xmlFile, categoryKey .. "#name")
        local categoryYoung = getXMLFloat(xmlFile, categoryKey .. "#young")
        local categoryMature = getXMLFloat(xmlFile, categoryKey .. "#mature")
        local categoryHarvested = getXMLFloat(xmlFile, categoryKey .. "#harvested")

        categories[categoryName] = {
            young = categoryYoung,
            mature = categoryMature,
            harvested = categoryHarvested
        }

        j = j+1
    end

    local i = 0
    while true do
        local cropKey = string.format("noTrespassing.crops.crop(%d)", i)
        if not hasXMLProperty(xmlFile, cropKey) then 
            break 
        end

        local cropName = getXMLString(xmlFile, cropKey .. "#name")
        local cropBase = getXMLFloat(xmlFile, cropKey .. "#base")
        local cropCategory = getXMLString(xmlFile, cropKey .. "#category")

        data.crops[cropName] = {
            base = cropBase,
            young = categories[cropCategory]["young"],
            mature = categories[cropCategory]["mature"],
            harvested = categories[cropCategory]["harvested"]
        }

        i = i+1
    end
    
    return data
end

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