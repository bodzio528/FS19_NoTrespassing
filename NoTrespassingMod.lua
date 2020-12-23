--[[

NoTrespassingMod.lua

This is file with NoTrespassingMod metatable (class) definition.

Author: bodzio528
Version: 0.1
Created: 2020-12-22

Changelog:
2020-12-22 initial version
]]

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
    
    self:loadCropsData()

    return self
end

function NoTrespassingMod:delete()
    print(string.format("%s", "NoTrespassingMod:delete()"))
    
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
        local cropSeed = getXMLFloat(xmlFile, cropKey .. "#seed")
        local cropYoung = getXMLFloat(xmlFile, cropKey .. "#young")
        local cropMature = getXMLFloat(xmlFile, cropKey .. "#mature")
        local cropHarvested = getXMLFloat(xmlFile, cropKey .. "#harvested")

        data.crops[cropName] = {
            base = cropBase,
            seed = cropSeed,
            young = cropYoung,
            mature = cropMature,
            harvested = cropHarvested
        }

        i = i+1
    end
    
    DebugUtil.printTableRecursively(data, "+", 0, 3, nil)

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

