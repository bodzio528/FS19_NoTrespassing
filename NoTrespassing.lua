--[[

No Trespassing Mod

Author: bodzio528
Version: 0.1
Created: 2020-12-16

Changelog:
2020-12-16 initial version
]]

NoTrespassing = {}

NoTrespassing.PENALTY_COOLDOWN = 5000.0 -- five seconds between paying compensation
NoTrespassing.WARNING_VISIBILITY_TIME = 5000.0

local NoTrespassing_MT = Class(NoTrespassing)

function NoTrespassing:new(mission, modDirectory, modName, i18n)
    local self = {}
    setmetatable(self, NoTrespassing_MT)

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()

    -- merge mod translations --
    local gi18nTextRef = getfenv(0).g_i18n.texts
    for key, text in pairs(i18n.texts) do
        gi18nTextRef[key] = text
    end

    return self
end

function NoTrespassing:delete()
end

function NoTrespassing.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Enterable, specializations) and SpecializationUtil.hasSpecialization(Motorized, specializations) and SpecializationUtil.hasSpecialization(Drivable, specializations)
end

function NoTrespassing.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", NoTrespassing)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", NoTrespassing)
end

function NoTrespassing:onLoad(savegame)
    local spec = self.spec_noTrespassing

    spec.penaltyCooldown = NoTrespassing.PENALTY_COOLDOWN

    spec.penalty = 0
    spec.totalPenalty = 0

    spec.isPlayerInside = false

    spec.displayWarning = false
end


function NoTrespassing:onReadStream(streamId, connection)
end

function NoTrespassing:onWriteStream(streamId, connection)
end

function NoTrespassing:onUpdate(dt)
    if not g_currentMission.missionInfo.fruitDestruction then
        -- player disabled crop damage in options, so why bother --
        return
    end

    if not self.spec_enterable.isEntered then
        -- only inflict damage if someone is inside vehicle --
        return
    end

    local spec = self.spec_noTrespassing

    if self.isClient and self:getIsActiveForInput(true) then
        -- print visible warning on screen --
        -- this is client-side function --
        if spec.displayWarning then
            if spec.totalPenalty > 0 then
                local text = string.format("%s (%s: %.0f)",
                                           g_i18n:getText("noTrespassing_warning_penalty"), 
                                           g_i18n:getText("noTrespassing_total_cost_label"), 
                                           math.floor(spec.totalPenalty))
                g_currentMission:showBlinkingWarning(text, NoTrespassing.WARNING_VISIBILITY_TIME)
            end
            spec.displayWarning = false
        else
            spec.totalPenalty = 0
        end
    end

    if self.isServer then
        -- call deduce penalty from bank account --
        spec.penaltyCooldown = spec.penaltyCooldown - dt
        if spec.penalty > 0 and spec.penaltyCooldown < 0 then
            local farmId = self:getOwnerFarmId() 
            local stats = g_farmManager:getFarmById(g_currentMission.player.farmId).stats 
            stats:updateStats("expenses", spec.penalty) 
            g_currentMission:addMoney(-spec.penalty, farmId, MoneyType.TRANSFER)

            spec.penaltyCooldown = NoTrespassing.PENALTY_COOLDOWN
            spec.penalty = 0
        end
    end

    local penalty = 0 -- variable for storing penalty for all wheels
    for k, wheel in pairs(self:getWheels()) do
        if self:getIsWheelFoliageDestructionAllowed(wheel) then -- this function checks AI helper drivinf over crops
            local width = 0.5 * wheel.width
            local length = math.min(0.5, 0.5 * wheel.width)
            local x, _, z = localToLocal(wheel.driveNode, wheel.repr, 0, 0, 0)

            local x0, y0, z0 = localToWorld(wheel.repr, x + width, 0, z - length) -- world coordinates of wheel center

            local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x0, z0)
            local farmland = g_farmlandManager:getFarmlandById(farmlandId)

            if farmland == nil then
                -- at least one wheel has contact with road - no damage (eg. driving wide combine harvesters) --
                return
            end

            if farmland.isOwned then
                -- drop procedure for owned fields --
                return
            end

            for f, field in pairs(g_fieldManager.farmlandIdFieldMapping[farmlandId]) do
                local mission = g_missionManager.fieldToMission[field.fieldId]
                if mission ~= nil and mission.farmId == self:getActiveFarm() then
                    -- field with active mission, stop --

                    spec.currentWarning = 0
                    spec.totalPenalty = 0
                    spec.penalty = 0

                    return
                end
            end

            local isOnField = wheel.densityType ~= 0
            if isOnField then
                penalty = penalty + getTyreBaseDamage(wheel, dt, self:getLastSpeed()) * getCropTypeCoeff(x0, z0)
            end
        end

        --[[ TODO: ADDITIONAL WHEELS ]]--
    end

    if penalty > 0 then
        spec.penalty = spec.penalty + penalty
        spec.totalPenalty = spec.totalPenalty + penalty
        spec.displayWarning = true
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

function NoTrespassing.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)

end