--[[

loader.lua

This is file with NoTrespassing mod initialization functions.

Author: bodzio528
Version: 0.1
Created: 2020-12-22

Changelog:
2020-12-22 initial version
2020-12-28 merge with register function file
2021-02-01 rewrite loader function, cleanup the code
]]

local debugActive = true

local modName = g_currentModName
local modDirectory = g_currentModDirectory
local specializationName = string.format("%s.noTrespassing", modName)

function onStartMission(mission)
    print(modName .. ":onStartMission()")

    print(string.format("%s:onStartMission(): I WONDER g_noTrespassing IS PRESENT = %s", modName, tostring(g_noTrespassing ~= nil)))

    if g_noTrespassing ~= nil then
        local path = Utils.getFilename("data/noTrespassingMaizePlus.xml", modDirectory)
        loadCropsData(path)
    end

    --local modSettingsPath = Utils.getFilename("noTrespassing.xml", modSettingsDir)
    --TODO: override with modSettingsPath
end

function finalizeVehicleTypes(vehicleTypesManager)
    print(modName .. ":finalizeVehicleTypes()")

    local numInserted = 0

    if specializationName ~= nil then
        local specializationObject = g_specializationManager:getSpecializationObjectByName(specializationName)
        if specializationObject ~= nil then
            for typeName, typeEntry in pairs(g_vehicleTypeManager.vehicleTypes) do
                if specializationObject.prerequisitesPresent(typeEntry.specializations) then
                    g_vehicleTypeManager:addSpecialization(typeName, specializationName)
                    numInserted = numInserted + 1

                    if debugActive then
                        print(string.format("%s: Specialization '%s' added to %s (%d)", modName, specializationName, typeName, numInserted))
                    end
                end
            end
        end
    end

    if debugActive then
        print(string.format("%s: Specialization '%s' added to %d vehicle types.", modName, specializationName, numInserted))
    end
end

function delete()
    print(modName .. ".delete()")

    getfenv(0)["g_noTrespassing"] = nil
end

function init()
    print(modName .. ".init()")

    if g_noTrespassing ~= nil then 
        return 
    end

    getfenv(0)["g_noTrespassing"] = {}

    g_specializationManager:addSpecialization("noTrespassing", "NoTrespassing", Utils.getFilename("NoTrespassing.lua", modDirectory), nil)

    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, delete)
    Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, onStartMission)
    VehicleTypeManager.finalizeVehicleTypes = Utils.prependedFunction(VehicleTypeManager.finalizeVehicleTypes, finalizeVehicleTypes)
end

init()

--------------------------------------------
--        LOAD XROPS DATA FROM XML        --
--------------------------------------------

function loadCropsData(path)
    print(modName .. ":loadCropsData() path = " .. path)

    if fileExists(path) then
        local xmlFile = loadXMLFile("noTrespassing", path)
        loadCropsDataFromXml(xmlFile)
        delete(xmlFile)
    end
end

function loadCropsDataFromXml(xmlFile)
    print(modName .. ":loadCropsDataFromXml()")

    -- provide sane defaults if xml is corrupted --
    local data = { 
        difficulty = { 0.75, 1.0, 1.5 },
        ground = 0.1,
        crops = {
            BARLEY  = {
                base=1.0,
                young=0.4,
                mature=1.0,
                harvested=0.1
            }
        }
    }

    -- start reading XML --

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

    -- no need to store categories, merge with crop data for faster lookup
    local categories = { CEREALS  = {young = 0.2, mature=1.0, harvested=0.1}} -- sane defaults if xml is corrupted
    local j = 0
    while true do
        local categoryKey = string.format("noTrespassing.categories.category(%d)", j)
        if not hasXMLProperty(xmlFile, categoryKey) then 
            break 
        end

        local categoryName = getXMLString(xmlFile, categoryKey .. "#name")
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
        if cropCategory == nil then
            cropCategory = "CEREALS"
        end

        data.crops[cropName] = {
            base = cropBase,
            young = categories[cropCategory]["young"],
            mature = categories[cropCategory]["mature"],
            harvested = categories[cropCategory]["harvested"]
        }

        i = i+1
    end
    
    getfenv(0)["g_noTrespassing"] = {}
    g_noTrespassing.data = data
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