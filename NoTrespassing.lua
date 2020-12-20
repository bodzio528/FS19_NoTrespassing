--[[

No Trespassing Mod

Author: bodzio528
Version: 0.1-private
Created: 2020-12-16

Changelog:
2020-12-16 initial version
]]

local modDirectory = g_currentModDirectory
local modName = g_currentModName

NoTrespassing = {}

NoTrespassing.PENALTY_COOLDOWN = 5000.0 -- five seconds between paying compensation
NoTrespassing.MISSION_COOLDOWN = 5000.0 -- fve seconds cooldown after entering active mission (no penalty)
NoTrespassing.WARNING_VISIBILITY_TIME = 5000.0
NoTrespassing.WARNING_TRESPASSING = 1
NoTrespassing.WARNING_PENALTY = 2
NoTrespassing.COST = "Total" -- g_i18n:getText("cost")

function NoTrespassing.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Enterable, specializations) and SpecializationUtil.hasSpecialization(Motorized, specializations) and SpecializationUtil.hasSpecialization(Drivable, specializations)
end

function NoTrespassing.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", NoTrespassing)
 --   SpecializationUtil.registerEventListener(vehicleType, "onUpdate", NoTrespassing) -- runs every frame (dt=16.67ms@60Hz)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", NoTrespassing)
end

function NoTrespassing:onLoad(savegame)
    print("NoTrespassing:onLoad()"..tostring(self:getActiveFarm()))

    self.lastPrintTime = 0
    self.dt = 0

    self.penalty = 0
    self.penaltyCooldown = NoTrespassing.PENALTY_COOLDOWN
    self.totalPenalty = 0

    self.missionCooldown = -1

    self.isPlayerInside = false

    self.currentWarning = 0
    self.warnings = {}
    self.warnings[NoTrespassing.WARNING_TRESPASSING] = "You do not own this land!" --g_i18n:getText("warning_trespassing")
    self.warnings[NoTrespassing.WARNING_PENALTY] = "Crops destroyed!" --g_i18n:getText("warning_penalty")
end

function NoTrespassing:onEnterVehicle(isControlling)
    if not self.isServer then 
        return 
    end

    if isControlling then
        self.isPlayerInside = true
    end
end

function NoTrespassing:onLeaveVehicle()
    if not self.isServer then 
        return 
    end

    self.isPlayerInside = false
end

function NoTrespassing:onUpdate(dt)
end

function NoTrespassing:onUpdateTick(dt)
    if self.isClient and self:getIsActiveForInput(true) then
        if self.currentWarning > 0 then
            local cost = ""
            if self.totalPenalty > 0 then
                cost = string.format(" %s: ", NoTrespassing.COST) .. tostring(math.floor(self.totalPenalty))
            end
            g_currentMission:showBlinkingWarning(self.warnings[self.currentWarning] .. cost, NoTrespassing.WARNING_VISIBILITY_TIME)
            self.currentWarning = 0
        else
            self.totalPenalty = 0
        end
    end

    if not self.isServer then 
        return 
    end

    if not g_currentMission.missionInfo.fruitDestruction then
        -- player disabled crop damage in options, so why bother
        return
    end

    if not self.isPlayerInside then
        return
    end

    -- call deduce penalty from bank account --
    self.penaltyCooldown = self.penaltyCooldown - dt
    if self.penalty > 0 and self.penaltyCooldown < 0 then
        local farmId = self:getOwnerFarmId() 
        local stats = g_farmManager:getFarmById(g_currentMission.player.farmId).stats 
        stats:updateStats("expenses", self.penalty) 
        g_currentMission:addMoney(-self.penalty, farmId, MoneyType.TRANSFER)

        self.penaltyCooldown = NoTrespassing.PENALTY_COOLDOWN
        self.penalty = 0
    end

    -- derease mission cooldown to avoid frequent search in mission manager (big, ugly, messy... pain to watch CPU performance dying here)
    self.missionCooldown = self.missionCooldown - dt
    if self.missionCooldown > 0 then return end

    local spec = self.spec_noTrespassing

    for k, wheel in pairs(self:getWheels()) do
        if self:getIsWheelFoliageDestructionAllowed(wheel) then -- this function disables AI helper crop destruction
            local width = 0.5 * wheel.width
            local length = math.min(0.5, 0.5 * wheel.width)
            local x, _, z = localToLocal(wheel.driveNode, wheel.repr, 0, 0, 0)

            local x0, y0, z0 = localToWorld(wheel.repr, x + width, 0, z - length)

            local mission = g_missionManager:getMissionAtWorldPosition(x0, z0)
            if mission ~= nil and mission.farmId == self:getActiveFarm() then
                self.missionCooldown = NoTrespassing.MISSION_COOLDOWN
                return
            end

            local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x0, z0)
            local farmland = g_farmlandManager:getFarmlandById(farmlandId)

            if farmland ~= nil then
                local farmlandOwnerId = g_farmlandManager:getFarmlandOwner(farmlandId)
                if farmlandOwnerId == FarmlandManager.NO_OWNER_FARM_ID then
                    self.currentWarning = math.max(self.currentWarning, NoTrespassing.WARNING_TRESPASSING)
                    local isOnField = wheel.densityType ~= 0
                    if isOnField then
                        local penalty = getTyreBaseDamage(wheel, dt, self:getLastSpeed()) * getCropTypeCoeff(x0, z0)
                        if penalty > 0 then
                            self.penalty = self.penalty + penalty
                            self.totalPenalty = self.totalPenalty + penalty
                            self.currentWarning = NoTrespassing.WARNING_PENALTY
                        end
                    end
                end
            else
                return -- at least one wheel has contact with road - no damage (eg. wide combine harvesters)
            end
        end

        if self.lastPrintTime < 0 then
            self.lastPrintTime = 10000
            
            local isOnField = wheel.densityType ~= 0
            local depth = wheel.lastColor[4]
            local color1 = wheel.lastColor[1]
            local color2 = wheel.lastColor[2]
            local color3 = wheel.lastColor[3]
            local terrainAttribute = wheel.lastTerrainAttribute

        end
        self.lastPrintTime = self.lastPrintTime - dt

        --[[ TODO: ADDITIONAL WHEELS ATTACHED ]]--
    end
end

function NoTrespassing:onWriteStream(streamId, connection)
    print(string.format("%s", "NoTrespassing:onWriteStream(streamId, connection)"))
end

function NoTrespassing:onReadStream(streamId, connection)
    print(string.format("%s", "NoTrespassing:onReadStream(streamId, connection)"))
end

function getGrowthStateCoeff(fruitDesc, state)
    if fruitDesc.destruction == nil then 
        return 0.0
    end

    if state == fruitDesc.destruction.state then
        return 0.01 --tiny fee for harvested ground
    end

    if state < fruitDesc.destruction.filterStart then
        return 0.25 -- fee for driving over first germination stages (sowed and germinated)
    end

    return 1.0
end

function getCropTypeCoeff(x, z) -- send fruits immune to damage there instead of calculating
    local modifier = g_currentMission.densityMapModifiers.cutFruitArea.modifier

    for index, fruit in pairs(g_currentMission.fruits) do
        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(index)

        modifier:resetDensityMapAndChannels(fruit.id, fruitDesc.startStateChannel, fruitDesc.numStateChannels)
        modifier:setParallelogramWorldCoords(x - 0.5, z - 0.5, 1,0, 0,1, "pvv")

        local area, totalArea, _ = modifier:executeGet()
        if area > 0 then
            local state = area / totalArea
            if "WEED" == fruitDesc.fruitName then 
                return 0.0 
            end
            if "GRASS" == fruitDesc.fruitName then 
                return 0.2
            end 
            if "SUGARCANE" == fruitDesc.fruitName then 
                return 0.5 * getGrowthStateCoeff(fruitDesc, state) 
            end
            if "POTATOE"  == fruitDesc.fruitName or "SUGARBEET" == fruitDesc.fruitName then 
                return 0.75 * getGrowthStateCoeff(fruitDesc, state) 
            end
            if "SUNFLOWER" == fruitDesc.fruitName then
                return 1.25 * getGrowthStateCoeff(fruitDesc, state) 
            end
            if "CANOLA" == fruitDesc.fruitName then
                return 1.5
            end
            return 1.0 * getGrowthStateCoeff(fruitDesc, state)
        end
    end
    return 1.0
end

function getTyreBaseDamage(wheel, dt, speed)
    if wheel.isCareWheel then
        return 0.0 -- narrow tires do not inflict damage to crops
    end

    if speed < 0.1 then
        return 0.0
    end

    -- todo: base it on travelled distance, where distance = speed * dt
    return wheel.width * dt * speed / 365.25
end
