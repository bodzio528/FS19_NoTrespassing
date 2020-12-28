--[[

NoTrespassingMod.lua

This is file with NoTrespassingMod metatable (class) definition.

Author: bodzio528
Version: 0.1
Created: 2020-12-22

Changelog:
2020-12-22 initial version
2020-12-28 merge with register function file
]]

local modName = g_currentModName
local modDirectory = g_currentModDirectory

local noTrespassingMod = nil
local function isEnabled() return 
    noTrespassingMod ~= nil 
end

NoTrespassingMod = {}
NoTrespassingMod.MY_CONSTANT = 20.0

local NoTrespassingMod_MT = Class(NoTrespassingMod)

function NoTrespassingMod:new(mission, modDirectory, modName, i18n)
    print(string.format("%s", "NoTrespassingMod:new()"))
    local self = setmetatable({}, NoTrespassingMod_MT)

    self.mission = mission

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()

    self.modDirectory = modDirectory
    self.modName = modName

    -- merge mod translations --
    local i18nRefGlobal = getfenv(0).g_i18n.texts
    for key, text in pairs(i18n.texts) do
        i18nRefGlobal[key] = text
    end
    
    print("NO_TRESPASSING LOAD XML DATA START")
    self:loadCropsData()

    DebugUtil.printTableRecursively(self.data, "+", 0, 3, nil)
    print("NO_TRESPASSING XML DATA DUMP END")

    self.statistics = { total = 0.0 }
    
    return self
end

function NoTrespassingMod:delete()
    print(string.format("%s", "NoTrespassingMod:delete()"))
end

function NoTrespassingMod:onMissionLoadFromSavegame(xmlFile)
    -- load some statistics
    print("NoTrespassingMod:onMissionLoadFromSavegame(xmlFile)")

    local statsTotalKey = "noTrespassing.statistics#total"
    if hasXMLProperty(xmlFile, statsTotalKey) then
        self.statistics.total = getXMLFloat(xmlFile, statsTotalKey)
        print(string.format("%s: loadedMission() STATISTICS TOTAL=%f", modName, self.statistics.total))
    end
end

function NoTrespassingMod:onMissionSaveToSavegame(xmlFile)
    -- save some statistics
    print(string.format("NoTrespassingMod:onMissionSaveToSavegame(xmlFile) STATISTICS=%f", self.statistics.total))

    setXMLFloat(xmlFile, "noTrespassing.statistics#total", self.statistics.total)
end

function NoTrespassingMod:loadCropsData()
    local path = Utils.getFilename("data/noTrespassing.xml", self.modDirectory)
    if fileExists(path) then
        local xmlFile = loadXMLFile("noTrespassing", path)
        self:loadCropsDataFromXml(xmlFile)
        delete(xmlFile)
    end
end

function NoTrespassingMod:loadCropsDataFromXml(xmlFile)
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

    local groundKey = "noTrespassing.ground"
    if hasXMLProperty(xmlFile, groundKey) then
        data.ground = getXMLFloat(xmlFile, groundKey .. "#base")
    end
        
    data.crops = {}

    local i = 0
    while true do
        local cropKey = string.format("noTrespassing.crops.crop(%d)", i)
        if not hasXMLProperty(xmlFile, cropKey) then 
            break 
        end

        local cropName = getXMLString(xmlFile, cropKey .. "#name")
        local cropBase = getXMLFloat(xmlFile, cropKey .. "#base")
        local cropYoung = getXMLFloat(xmlFile, cropKey .. "#young")
        local cropMature = getXMLFloat(xmlFile, cropKey .. "#mature")
        local cropHarvested = getXMLFloat(xmlFile, cropKey .. "#harvested")

        data.crops[cropName] = {
            base = cropBase,
            young = cropYoung,
            mature = cropMature,
            harvested = cropHarvested
        }

        i = i+1
    end
    

    self.data = data
end

function NoTrespassingMod.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    print(string.format("%s", "NoTrespassingMod.installSpecializations()"))

    specializationManager:addSpecialization("noTrespassing", "NoTrespassing", Utils.getFilename("NoTrespassing.lua", modDirectory), nil)

    for vehicleName, vehicleType in pairs(vehicleTypeManager:getVehicleTypes()) do
        local isDrivable = SpecializationUtil.hasSpecialization(Drivable, vehicleType.specializations)
        local isEnterable = SpecializationUtil.hasSpecialization(Enterable, vehicleType.specializations)
        local isMotorized = SpecializationUtil.hasSpecialization(Motorized, vehicleType.specializations)
        local isSplineVehicle = SpecializationUtil.hasSpecialization(SplineVehicle, vehicleType.specializations)
            
        if isDrivable and isEnterable and isMotorized and not isSplineVehicle then
            vehicleTypeManager:addSpecialization(vehicleName, modName .. ".noTrespassing")
            print(string.format("%s: spec noTrespassing added to vehicle %s", "NoTrespassingMod.installSpecializations()", vehicleName))
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
            noTrespassingMod:onMissionSaveToSavegame(xmlFile) -- fil data from noTrespassingMod class instance
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